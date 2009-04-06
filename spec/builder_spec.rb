require 'activesupport'
require 'big_sitemap/builder'

describe BigSitemap::Builder do
  describe "basics" do
    before do
      @xml = described_class.new(:indent => 2, :max_urls => 2)
      @time = Time.now
      @time_string = @time.to_s(:sitemap)
    end
  
    it "should add location" do
      @xml.add_url!("http://example.com/mooslav", :time => @time)
      @xml.close!
    
      result.should == strip(<<-XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>http://example.com/mooslav</loc>
            <lastmod>#{@time_string}</lastmod>
          </url>
        </urlset>
      XML
    end
    
    it "should support frequency" do
      @xml.add_url!("http://example.com/mooslav", :frequency => "all the f-in time")
      @xml.close!
      result.should include("<changefreq>all the f-in time</changefreq>")
    end
    
    it "should support priority" do
      @xml.add_url!("http://example.com/mooslav", :priority => 0.6)
      @xml.close!
      result.should include("<priority>0.6</priority>")
    end
  
    it "should rotate files when it reaches maximum number of URLs" do
      @xml.add_url!("http://example.com/loc1")
      @xml.add_url!("http://example.com/loc2")
      @xml.add_url!("http://example.com/loc3")
      @xml.close!
      result.scan('<urlset').size.should == 2
    end
  end
  
  it "should have sitemap index mode" do
    @xml = described_class.new(:indent => 2, :type => 'index')
    @xml.add_url!("/sitemap1.xml")
    @xml.close!
    
    result.should == strip(<<-XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>/sitemap1.xml</loc>
        </sitemap>
      </sitemapindex>
    XML
  end
  
  # strips leading whitespace from a code block
  def strip(xml)
    whitespace = xml.match(/^\s+/)[0]
    xml.gsub(/^#{whitespace}/m, '')
  end
  
  def result
    @xml.target!
  end
end
