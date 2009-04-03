require 'uri'
require 'zlib'
require 'builder'
require 'fileutils'

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => 50000,
    :batch_size => 1001,
    :gzip => true, # set false to inspect results
    
    # opinionated
    :ping_google => true,
    :ping_yahoo => false, # needs :yahoo_app_id
    :ping_msn => false
  }
  
  TIMESTAMP_COLUMNS = %w(updated_at updated_on updated created_at created_on created)
  
  include ActionController::UrlWriter
  
  class Builder < Builder::XmlMarkup
    # add support for:
    #   xml.open_foo!(attrs)
    #   xml.close_foo!
    def method_missing(method, *args, &block)
      if method.to_s =~ /^(open|close)_(.+)!$/
        operation, name = $1, $2
        name = "#{name}:#{args.shift}" if Symbol === args.first
        
        if 'open' == operation
          _indent
          _start_tag(name, args.first)
          _newline
          @level += 1
        else
          @level -= 1
          _indent
          _end_tag(name)
          _newline
        end
      else
        super
      end
    end
  end
  
  def initialize(options = {})
    @options = DEFAULTS.merge options
    
    if @options[:batch_size] > @options[:max_per_sitemap]
      raise ArgumentError, '":batch_size" must be less than ":max_per_sitemap"'
    end
    
    if @options[:url_options]
      default_url_options.update @options[:url_options]
    elsif @options[:base_url]
      uri = URI.parse(@options[:base_url])
      default_url_options[:host] = uri.host
      default_url_options[:port] = uri.port
      default_url_options[:protocol] = uri.scheme
    else
      raise ArgumentError, 'you must specify either ":url_options" hash or ":base_url" string'
    end
    
    @root = @options[:document_root] || Rails.public_path
    @sources = []
    @sitemap_files = []
    
    # W3C format is the subset of ISO 8601
    Time::DATE_FORMATS[:sitemap] = lambda { |time|
      time.strftime "%Y-%m-%dT%H:%M:%S#{time.formatted_offset(true, 'Z')}"
    }
  end

  def add(model, options = {})
    @sources << [model, options.dup]
  end

  def clean
    Dir["#{@root}/sitemap_*.{xml,xml.gz}"].each do |file|
      FileUtils.rm file, :verbose => true
    end
  end

  def generate
    for model, options in @sources
      with_sitemap(model.name.tableize) do
        find_options = options.dup
        changefreq = find_options.delete(:change_frequency) || 'weekly'
        find_options[:batch_size] ||= @options[:batch_size]
        timestamp_column = model.column_names.find { |col| TIMESTAMP_COLUMNS.include? col }
      
        model.find_each(find_options) do |record|
          last_updated = record.read_attribute(timestamp_column)
          add_url(polymorphic_url(record), last_updated, changefreq)
        end
      end
    end

    generate_sitemap_index
  end

  private
  
    def with_sitemap(name)
      @sitemap = "sitemap_#{name}"
      @parts = 0
      @urls = 0
      init_part
      begin
        yield
      ensure
        close_part
      end
    end
    
    def init_part
      part_filename = @sitemap
      part_filename += "_#{@parts}" if @parts > 0
      
      @xml = Builder.new(:target => xml_open(part_filename), :indent => 2)
      @xml.instruct!
      @xml.open_urlset!(:xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9')
    end
    
    def add_url(url, time, freq)
      rotate_parts! if @options[:max_per_sitemap] == @urls
      
      @xml.url do
        @xml.loc url
        @xml.lastmod time.to_s(:sitemap)
        @xml.changefreq freq
      end
      @urls += 1
    end
    
    def close_part
      @xml.close_urlset!
      @xml.target!.close
    end
    
    def rotate_parts!
      close_part
      @urls = 0
      @parts += 1
      init_part
    end

    def xml_open(filename)
      filename += '.xml'
      filename << '.gz' if @options[:gzip]
      file = File.open("#{@root}/#{filename}", 'w+')
      @sitemap_files << file.path
      writer = @options[:gzip] ? Zlib::GzipWriter.new(file) : file
      
      if block_given?
        yield writer 
        writer.close
      end
      writer
    end

    def generate_sitemap_index
      xml_open 'sitemap_index' do |file|
        xml = Builder.new(:target => file, :indent => 2)
        xml.instruct!
        xml.sitemapindex(:xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9') do
          for path in @sitemap_files[0..-2]
            xml.sitemap do
              xml.loc url_for_sitemap(path)
              xml.lastmod File.stat(path).mtime.to_s(:sitemap)
            end
          end
        end
      end
    end
    
    def url_for_sitemap(path)
      root_url + File.basename(path)
    end
    
    def root_url
      @root_url ||= begin
        url = ''
        url << (default_url_options[:protocol] || 'http')
        url << '://' unless url.match('://')
        url << default_url_options[:host]
        url << ":#{port}" if port = default_url_options[:port] and port != 80
        url << '/'
      end
    end

    def ping_search_engines
      require 'net/http'
      require 'cgi'
      
      sitemap_uri = CGI::escape(url_for_sitemap(@sitemap_files.last))
      
      if @options[:ping_google]
        Net::HTTP.get('www.google.com', "/webmasters/tools/ping?sitemap=#{sitemap_uri}")
      end
      
      if @options[:ping_yahoo]
        if @options[:yahoo_app_id]
          Net::HTTP.get('search.yahooapis.com', "/SiteExplorerService/V1/updateNotification?" +
            "appid=#{@options[:yahoo_app_id]}&url=#{sitemap_uri}")
        else
          $stderr.puts 'unable to ping Yahoo: no ":yahoo_app_id" provided' 
        end
      end
      
      if @options[:ping_msn]
        Net::HTTP.get('webmaster.live.com', "/ping.aspx?siteMap=#{sitemap_uri}")
      end
    end
end