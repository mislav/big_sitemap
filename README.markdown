# BigSitemap

BigSitemap is a [Sitemap](http://sitemaps.org) generator suitable for Rails 2.3.2 applications with more than 50000 URLs.  It splits large sitemaps into multiple files, optionally gzipping them to minimize bandwidth usage and using batched queries (`find_each`) on your models to avoid running out of memory.

BigSitemap is best run periodically through a Rake/Thor task. Your application environment should be loaded prior to generating sitemaps; BigSitemap uses your application database models and routing setup.

    sitemap = BigSitemap.new(
      :url_options => { :host => 'example.com' },
      :batch_size => 1001, :gzip => false
    )
    
    # add a model with find options
    sitemap.add(Community, :conditions => ['members_count > ?', 5])
    
    # named scopes also work
    sitemap.add(Posts.published, :change_frequency => 'weekly')
    
    # generate it!
    sitemap.generate
    
The code above will create 3 files at minimum:

1. public/sitemap_index.xml
2. public/sitemap_communities.xml
3. public/sitemap_posts.xml

If any of your sitemaps grow beyond 50000 URLs (this limit can be changed to less with the ":max\_per\_sitemap" option), the sitemap files will be partitioned into multiple files ("sitemap\_communities\_1.xml", "sitemap\_communities\_2.xml", ...).

The URLs for each database record are generated with `polymorphic_url` helper from Rails. That means that the URL for a record will be exactly what you would expect: generated with respect to the routing setup of your app.

## Advanced

BigSitemap options:

* `:url_options` -- hash with `:host`, optionally `:port` and `:protocol`;
* `:base_url` -- string alternative to `:url_options`, e.g. "https://example.com:8080/";
* `:document_root` -- value of `Rails.public_path` by default (recommended not to change);
* `:max_per_sitemap` -- 50000, limit dictated by Google but can be less;
* `:batch_size` -- 1001;
* `:gzip` -- true;
* `:ping_google` -- true;
* `:ping_yahoo` -- false, needs `:yahoo_app_id`;
* `:ping_msn` -- false.

To ping search engines, call `ping_search_engines` after you generated the sitemap:

    sitemap.generate
    sitemap.ping_search_engines

You can control "changefreq" and "priority" values for each record individually by passing lambdas instead of fixed values:

    sitemap.add( Posts,
      :change_frequency => lambda {|post| ... },
      :priority => lambda {|post| ... }
    )

## Credits

Thanks to Alex Rabarts who open-sourced big_sitemap on GitHub.

Thanks to Alastair Brunton and Harry Love [whose work was a starting point for big_sitemap](http://scoop.cheerfactory.co.uk/2008/02/26/google-sitemap-generator/).

Copyright (c) 2009 Stateless Systems (http://statelesssystems.com). See LICENSE for details.
