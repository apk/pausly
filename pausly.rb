require 'webrick'
require_relative 'htmltools'

module Pausly

  class Server
    attr_reader :prefix

    def initialize(iogen: Io, prefix: nil)
      @iogen=iogen
      @prefix=prefix ? prefix.split('/',-1) : ['']
      @tree={}
    end

    def add_service(mod)
      mod.constants.each do |c|
        s=c.to_s
        if s =~ /\AU_/
          h=$'
          # A trailing _ means that the URL must have a trailing /
          # but we must special-case a single _ b/c that would require
          # // in the URL otherwise. Ugly, admittedly.
          n=(h=='_' ? [''] : h.gsub('D','.').split('_',-1))
          # puts "#{c.inspect} => #{h.inspect} => #{n.inspect}"
          r=mod.const_get(c)
          # puts "#{n.inspect}: #{r.new.inspect}"
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
            STDERR.puts puts "Double #{n.inspect}"
          else
            p[:serve]=r
          end
        end
      end
      # puts @tree.inspect
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
          unless block_given? and yield a
            STDERR.puts "run_webrick: bad arg #{a.inspect}"
          end
        end
      end

      server = WEBrick::HTTPServer.new Port: port, BindAddress: addr
      server.mount '/', self
      server.start # Won't return; does the service
    end

    def do_op(meth,req,resp)
      q=req.path.split('/',-1)
      q=[''] if q==['',''] # TODO: Still ugly, or
      #               you need the 'class U__ <U_; end' :-(
      # puts "P: #{@prefix.inspect}"
      # puts "Q: #{q.inspect}"

      # Check whether operation prefix matches actual prefix
      @prefix.each do |p|
        unless p == q.shift
          resp.status=500
          resp.body="Internal server (prefix) error\nFrontend misconfiguration\n"
          return
        end
      end
      args=[]
      p=@tree
      # puts "T: #{@tree.inspect}"
      q.each do |c|
        c=c.gsub(/\$([2-7][0-9a-f])/) { $1.to_i(16).chr }
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
          begin
            me=p.instance_method(meth)
          rescue NameError
            resp.status=405
            resp.body="Method not allowed\n"
            return
          end
          wrap(me.bind(p.new),req,resp,args)
          return
        end
      end
      resp.status=404
      resp.body="Not found\n"+req.path.inspect
    end

    def wrap(ob,rq,rp,args)
      headers={}
      rp.status=201
      begin

        io=@iogen.new(rq,self)
        ob.call(io,*args)

        body=io.body.to_html
        headers=io.headers
        rp.status=(io.status || 200)

      rescue Reply => e
        rp.status=e.code
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

      io.head.tag('title').add(io.title || '--untitled--')
      rp.body="<!doctype html>\n<html>#{io.head.to_html}#{body}</html>\n"
    end

    def wrap_htmlesc(s)
      s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;')
    end
  end

  class Io
    attr_reader :cookies, :ip, :status, :headers, :method, :head, :body, :data
    attr_accessor :title

    def path
      @request.path
    end

    def initialize(rq,sv)
      @title=nil
      @status=nil
      @server=sv
      @request=rq
      @cookies={}
      @method=rq.request_method
      @head=HtmlTools::Tag.new('head')
      @head.tag('meta', name: 'viewport', content: 'width=device-width')
      @body=HtmlTools::Tag.new('body')
      @headers={}
      @data=nil

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

    def not_found
      @status=404
    end

    def mkurl(*a)
      # puts "mkurl(#{@server.prefix.inspect}, #{a.inspect})"

      # Assuming only ascii printables in the RE
      a=a.map {|x| x.gsub(/[\?\&\$\/]/) {|c| '$'+c.ord.to_s(16) } }

      r=(@server.prefix+a).join('/')
      # puts "    r:#{r.inspect}"
      r='/' if r == '' # TODO: Ugly
      r
    end

    def query_param(n=nil)
      if n
        @request.query[n]
      else
        @request.query
      end
    end
  end

  class Reply < RuntimeError
    attr_reader :headers, :code, :data

    def initialize(data,c=200,**headers)
      @headers=headers
      @code=c
      @data=data
    end
  end

  class NotFoundReply < Reply
    def initialize
      super("Not found\n", c=404)
      @headers['Content-Type']='text/plain'
    end
  end

  class RedirectReply < Reply
    def initialize(l,c=303,**headers)
      super('',c,**headers)
      @headers['Location']=(l == '' ? '.' : l)
    end
  end

  class DataReply < Reply
    def initialize(type, data, **headers)
      super(data,**headers)
      @headers['Content-Type']=type
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

