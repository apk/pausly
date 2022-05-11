
module HtmlTools

  # A literal string that returns
  # itself from to_html, suitable
  # to get HTML contents into Tags.
  class LitStr <String
    def to_html
      return self
    end
  end

  def self.escapeHTML(x)
    x.
      gsub('&','&amp;').
      gsub('<','&lt;').
      gsub('>','&gt;')
  end

  NBSP=LitStr.new('&nbsp;')

  # Represents a HTML tag with attrs and content.
  class Tag
    # Tag constructor. Parameters: Tag name and
    # an optional hash of attributes, i.e.
    # `Tag.new('span', id: 'that', class: 'hdr")`
    # A block given to the ctor is evaluated in the
    # context of the new tag object, making things like
    #    Tag.new('tr') do
    #       tag('td').add('value1')
    #       tag('td').add('value2')
    #       tag('td').add('value3')
    #    end
    # possible. Locally-visible methods are made accesible as explained in
    # https://www.dan-manges.com/blog/ruby-dsls-instance-eval-with-delegation
    # and surrounding variables are visible as by ruby. Only instance vars
    # are *not* accessible. (There seems to be no trick in ruby to do that.)
    def initialize(n,attrs={},&blk)
      @name=n
      @attrs=attrs || {}
      @body=[]
      if blk
        @real=eval 'self', blk.binding
        instance_eval &blk
      end
    end

    def method_missing(meth, *args, &blk)
      @real.send(meth, *args, &blk)
    end

    # Return the surrounding tag, useful
    # only inside do blocks.
    def this
      self
    end

    # Set attributes, arg is a hash that is
    # merged into previous attrs.
    def attr(attrs)
      @attrs.merge! attrs
    end

    # Add elements (strings or sub-entities)
    # to a tag. Content must either be a string
    # (which will be properly html-quoted) or
    # something that responds to to_html (as Tag does).
    def add(*x)
      @body+=x
      self
    end

    # Add a string to the tag's body, replacing spaces
    # with &nbsp; entities.
    def add_nbsp(s)
      a=[]
      while s =~ / /
        x=$`
        a.push(x) if x != ''
        a.push(NBSP)
        s=$'
      end
      a.push(s) if s != ''
      add(*a)
    end

    # Create new tag and add to the current object,
    # parameters as with Tag.new.
    def tag(n,attr={}, &blk)
      t=Tag.new(n,attr,&blk)
      add(t)
      t
    end

    # Add as raw HTML, not to be escaped.
    def add_html(x)
      add(LitStr.new(x))
    end

    # Convert the Tag into HTML. Tries some
    # linebreaking inside the tags to avoid
    # lines getting too long.
    def to_html
      cnt=@body.map do |x|
        if x.instance_of? String
          HtmlTools.escapeHTML(x)
        elsif x.respond_to? :to_html
          x.to_html
        else
          HtmlTools.escapeHTML(x.inspect)
        end
      end.join('')
      cnt+='</'+@name+'>'
      hd='<'+@name
      @attrs.each_pair do |k,v|
        if v.instance_of? String
          t='"'+HtmlTools.escapeHTML(v)+'"'
        else
          t=v.to_s
        end
        if k.instance_of? String
          u=k
        else
          u=k.to_s.gsub('_','-')
        end
        hd+=' '+u+'='+t
      end
      hd+="\n" if cnt.length > 60
      hd+'>'+cnt
    end
  end

end
