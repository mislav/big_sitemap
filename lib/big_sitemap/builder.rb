require 'builder'
require 'zlib'

class BigSitemap
  class Builder < Builder::XmlMarkup
    MAX_URLS = 50000
    
    def initialize(options)
      @gzip = options.delete(:gzip)
      @max_urls = options.delete(:max_urls) || MAX_URLS
      @type = options.delete(:type)
      @paths = []
      @parts = 0
      
      if @filename = options.delete(:filename)
        options[:target] = _get_writer        
      end
      
      super(options)
      
      @opened_tags = []
      _init_document
    end
    
    def index?
      @type == 'index'
    end
    
    def video?
      @type == 'video'
    end
    
    def add_url!(url, options = {})
      _rotate if @max_urls == @urls
      
      tag!(index?? 'sitemap' : 'url') do
        loc(url)
        lastmod(options[:time].to_s(:sitemap)) if options[:time]
        changefreq(options[:frequency]) if options[:frequency]
        priority(options[:priority]) if options[:priority]
        _build_video(options[:video]) if video?
      end
      @urls += 1
    end
    
    def close!
      _close_document
      target!.close if target!.respond_to?(:close)
    end
    
    def paths!
      @paths
    end
    
    private
    
    def _get_writer
      if @filename
        filename = @filename.dup
        filename << "_#{@parts}" if @parts > 0
        filename << '.xml'
        filename << '.gz' if @gzip
        _open_writer(filename)
      else
        target!
      end
    end
    
    def _open_writer(filename)
      file = File.open(filename, 'w+')
      @paths << filename
      @gzip ? Zlib::GzipWriter.new(file) : file
    end
    
    def _init_document
      @urls = 0
      instruct!
      # define root element and namespaces
      attrs = {'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9'}
      attrs['xmlns:video'] = 'http://www.google.com/schemas/sitemap-video/1.1' if video?
      _open_tag(index?? 'sitemapindex' : 'urlset', attrs)
    end
    
    def _rotate
      # write out the current document and start writing into a new file
      close!
      @parts += 1
      @target = _get_writer
      _init_document
    end
    
    # add support for:
    #   xml.open_foo!(attrs)
    #   xml.close_foo!
    def method_missing(method, *args, &block)
      if method.to_s =~ /^(open|close)_(.+)!$/
        operation, name = $1, $2
        name = "#{name}:#{args.shift}" if Symbol === args.first
        
        if 'open' == operation
          _open_tag(name, args.first)
        else
          _close_tag(name)
        end
      else
        super
      end
    end
    
    # opens a tag, bumps up level but doesn't require a block
    def _open_tag(name, attrs)
      _indent
      _start_tag(name, attrs)
      _newline
      @level += 1
      @opened_tags << name
    end
    
    # closes a tag block by decreasing the level and inserting a close tag
    def _close_tag(name)
      @opened_tags.pop
      @level -= 1
      _indent
      _end_tag(name)
      _newline
    end
    
    def _close_document
      for name in @opened_tags.reverse
        _close_tag(name)
      end
    end
    
    def _build_video(data)
      return if data.nil? or data.empty?
      
      video :video do
        video :content_loc, data[:url] if data[:url]
        video :player_loc, data[:player_url], :allow_embed => "yes" if data[:player_url]
        video :thumbnail_loc, data[:thumbnail_url] if data[:thumbnail_url]
        
        video :title, data[:title] if data[:title]
        video :description, data[:description] if data[:description]
        video :rating, data[:rating] if data[:rating]
        video :view_count, data[:views] if data[:views]
        video :publication_date, data[:published_at].to_s(:sitemap) if data[:published_at]
        video :duration, data[:length] if data[:length]
        
        if data[:tags]
          for tag in data[:tags]
            video :tag, tag
          end
        end
        
        unless data[:family_friendly].nil?
          video :family_friendly, data[:family_friendly] ? 'yes' : 'no'
        end
        video :category, data[:category] if data[:category]
      end
    end
  end
end

# W3C format is the subset of ISO 8601
Time::DATE_FORMATS[:sitemap] = lambda { |time|
  time.strftime "%Y-%m-%dT%H:%M:%S#{time.formatted_offset(true, 'Z')}"
}
