require 'stringio'
require 'activesupport'

unless defined? ActionController
  module ActionController
    module UrlWriter
      def self.included(base)
        class << base
          def default_url_options
            @default_url_options ||= {}
          end
        end
      end
      
      def default_url_options
        self.class.default_url_options
      end
      
      def polymorphic_url(obj)
        nil
      end
    end
  end
end

require 'big_sitemap'

describe BigSitemap do
  subject {
    described_class.new(
      :url_options => { :host => 'example.com' },
      :document_root => File.dirname(__FILE__)
    )
  }
  
  it "initializes URL options" do
    subject.default_url_options[:host].should == 'example.com'
  end
end

describe BigSitemap::Builder do
  subject {
    @xml = described_class.new(:indent => 2)
    @xml.target!
  }
  
  it "should support nested tags without restricting to a block" do
    should == ""
    @xml.open_foo!(:a => 'b')
    @xml.bar("Hello")
    @xml.close_foo!
    should == %(<foo a="b">\n  <bar>Hello</bar>\n</foo>\n)
  end
end
