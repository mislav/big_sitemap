require 'uri'
require 'fileutils'
require 'big_sitemap/builder'

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => Builder::MAX_URLS,
    :batch_size => 1001,
    :gzip => true, # set false to inspect results
    
    # opinionated
    :ping_google => true,
    :ping_yahoo => false, # needs :yahoo_app_id
    :ping_msn => false
  }
  
  TIMESTAMP_COLUMNS = %w(updated_at updated_on updated created_at created_on created)
  
  include ActionController::UrlWriter
  
  def initialize(options = {})
    @options = DEFAULTS.merge options
    
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
      with_sitemap(model.name.tableize) do |sitemap|
        find_options = options.dup
        changefreq = find_options.delete(:change_frequency) || 'weekly'
        priority = find_options.delete(:priority)
        
        find_options[:batch_size] ||= @options[:batch_size]
        timestamp_column = model.column_names.find { |col| TIMESTAMP_COLUMNS.include? col }
      
        model.find_each(find_options) do |record|
          last_updated = timestamp_column && record.read_attribute(timestamp_column)
          freq = changefreq.is_a?(Proc) ? changefreq.call(record) : changefreq
          pri = priority.is_a?(Proc) ? priority.call(record) : priority
          
          sitemap.add_url!(polymorphic_url(record), last_updated, freq, pri)
        end
      end
    end

    generate_sitemap_index
  end

  private
  
    def with_sitemap(name, options = {})
      options[:filename] = "#{@root}/sitemap_#{name}"
      options[:max_urls] = @options[:max_per_sitemap]
      
      unless options[:gzip] = @options[:gzip]
        options[:indent] = 2
      end
      
      sitemap = Builder.new(options)
      
      begin
        yield sitemap
      ensure
        sitemap.close!
        @sitemap_files.concat sitemap.paths!
      end
    end

    def generate_sitemap_index
      with_sitemap 'index', :type => 'index' do |sitemap|
        for path in @sitemap_files
          sitemap.add_url!(url_for_sitemap(path), File.stat(path).mtime)
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