require 'webrick'
require_relative 'htmltools'

module Pausly

  class Server
    def initialize(wrap:nil, prefix: nil)
      @wrap=wrap||Wrapping.new
      @prefix=prefix ? prefix.split('/',-1) : ['']
puts "prefix: #{@prefix.inspect}"
      @tree={}
    end

    def add_service(mod)
      mod.constants.each do |c|
        s=c.to_s
        if s =~ /\AU_/
          n=$'.gsub('D','.').split('_')
          puts c.inspect
          r=mod.const_get(c)
          puts "#{n.inspect}: #{r.new.inspect}"
          p=@tree
          n.each do |m|
            if m == 'N'
              p=(p[:int]||={})
            elsif m == 'A'
              p=(p[:any]||={})
            else
              p=(p[m]||={})
            end
          end
          if p[:serve]
            puts "Double"
          else
            p[:serve]=r
          end
        end
      end
      puts @tree.inspect
      self
    end

    def get_instance(x)
      Shim.new(self,x)
    end

    def run_webrick(args)
      port=4040
      addr='0.0.0.0'
      args.each do |a|
        case a
        when /\Aaddr=/
          addr=$'
        when /\Aport=(\d+)\Z/
          port=$1.to_i
        else
          STDERR.puts "run_webrick: bad arg #{a.inspect}"
        end
      end

      server = WEBrick::HTTPServer.new Port: port, BindAddress: addr
      server.mount '/', self
      server.start # Won't return; does the service
    end

    def do_op(meth,req,resp)
      q=req.path.split('/',-1)
      p=@tree
      args=[]
      i=0
      @prefix.each do |p|
        unless p == q.shift
          resp.status=500
          resp.body="Internal server (path) error\n"
          return
        end
      end
      q.each do |c|
        pi=@prefix[i]
        if pi
          next if pi == c
        end
        next if c == '' # TODO: Only at the prefix!
        q=p[c]
        if q
          p=q
          next
        end
        q=p[:int]
        if q
          if c =~ /\A[0-9]+\Z/
            p=q
            args.push(c.to_i)
            next
          end
        end
        q=p[:any]
        if q
          p=q
          args.push(c)
          next
        end
        p=nil
        break
      end
      if p
        p=p[:serve]
        if p
          puts "P: #{p.inspect}"
          begin
            me=p.instance_method(meth)
          rescue NameError
            resp.status=405
            resp.body="Method not allowed\n"
            return
          end
          @wrap.wrap(me.bind(p.new),req,resp,args)
          return
        end
      end
      resp.status=404
      resp.body="Not found\n"
    end
  end

  class Io
    attr_reader :cookies, :ip, :status, :headers, :method, :body, :request

    def initialize(rq)
      @request=rq
      @cookies={}
      @method=rq.request_method
      @body=HtmlTools::Tag.new('body')
      @headers={}

      c=rq['Cookie']
      if c
        c.split('; ').each do |x|
          a=x.split('=',2)
          if a.size == 2
            @cookies[a[0]]=a[1]
          end
        end
      end
    end
  end

  class Wrapping

    def initialize
      @iomaker=nil
    end

    class Redirect < RuntimeError
      attr_reader :headers, :code

      def initialize(l,c=303,**headers)
        @headers=headers
        @headers['Location']=(l == '' ? '.' : l)
        @code=c
      end
    end

    class Data < RuntimeError
      attr_reader :headers, :data
      def initialize(type, data, **headers)
        @headers=headers
        @headers['Content-Type']=type
        @data=data
      end
    end

    def wrap_htmlesc(s)
      s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;')
    end

    def wrap(ob,rq,rp,args)
      headers={}
      rp.status=201
      begin

        io=(@iomaker || Io).new(rq)
        ob.call(io,*args)

        body=io.body.to_html
        headers=io.headers
        rp.status=(io.status || 200)

      rescue Redirect => e
        rp.status=e.code
        e.headers.each_pair do |k,v|
          rp[k]=v
        end
        rp.body=''
        return

      rescue Data => e
        rp.status=200
        e.headers.each_pair do |k,v|
          rp[k]=v
        end
        rp.body=e.data
        return

      rescue Exception => e
        rp.status=500
        STDERR.puts 'Exception: '+e.inspect
        e.backtrace.each do |b|
          STDERR.puts '    at: '+b.inspect
        end
        begin
          body='
<div class="head">
<span class="title">Error</span>
<a href="." class="pseudobutton">Home</a>
</div>
<div class="error">'+[e.inspect,*e.backtrace].map{|x| wrap_htmlesc(x) }.join("<br>\n")+'</div>'
        rescue Exception => ee
          body=wrap_htmlesc(ee.to_s)
        end
        body='<body>'+body+'</body>'
      end

      rp['Content-type']='text/html; charset=utf-8'

      headers.each do |k,v|
        rp[k]=v
        if k == 'Status'
          STDERR.puts 'OOPS'
        end
      end

      rp.body="<!doctype html public \"-//w3c//dtd html 4.0 transitional//en\">
<html>
<head>
<meta name='viewport' content='width=device-width'>
<title>TODO</title>
<link rel='stylesheet' type='text/css' href='$css'>
</head>#{body}</html>
"
    end
  end

  class Shim < WEBrick::HTTPServlet::AbstractServlet

    def initialize(s,x)
      @my=s
      super(x)
    end

    def do_GET(req, resp)
      @my.do_op(:do_get,req,resp)
    end

    def do_PUT(req, resp)
      @my.do_op(:do_put,req,resp)
    end

    def do_POST(req, resp)
      @my.do_op(:do_post,req,resp)
    end

    def do_DELETE(req, resp)
      @my.do_op(:do_delete,req,resp)
    end
  end

end

