use strict;
use warnings;

$|++;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'testing';
};

use Test::Mojo;
use Test::More tests => 154;
use Mojolicious::Lite;
use Mojo::ByteStream ('b');
use lib '../lib';

our ($rss, $rdf, $atom);

use_ok('Mojolicious::Plugin::PubSubHubbub');
use_ok('Mojo::DOM');

my $self_href = 'http://sojolicio.us/blog';

# Add topics in RSS
my $dom = Mojo::DOM->new(xml => 1)->parse($rss);

Mojolicious::Plugin::PubSubHubbub::_add_topics('rss',
					       $dom,
					       $self_href);

is($dom->find('item')->size,
   $dom->find('item > source > link[rel="self"]')->size,
   'Add topics to RSS');

is($dom->find('link[rel="self"][href="http://sojolicio.us/2/blog"]')->size,
   1, 'Add topics to RSS 2' );
is($dom->find('link[rel="self"][href="http://sojolicio.us/blog"]')->size,
   2, 'Add topics to RSS 3' );

# Add topics in atom
$dom = $dom->parse($atom);
Mojolicious::Plugin::PubSubHubbub::_add_topics('atom',
					       $dom,
					       $self_href);
is($dom->find('entry')->size,
   $dom->find('entry > source > link[rel="self"]')->size,
   'Add topics to Atom');
is($dom->find('link[rel="self"][href="http://sojolicio.us/2/blog"]')->size,
   1, 'Add topics to Atom 2' );
is($dom->find('link[rel="self"][href="http://sojolicio.us/blog"]')->size,
   2, 'Add topics to Atom 3' );

# Add topics in RDF/RSS
$dom = $dom->parse($rdf);
Mojolicious::Plugin::PubSubHubbub::_add_topics('atom',
					       $dom,
					       $self_href);
is($dom->find('item')->size,
   $dom->find('item > source > link[rel="self"]')->size,
   'Add topics to RDF/RSS');
is($dom->find('link[rel="self"][href="http://sojolicio.us/2/blog"]')->size,
   1, 'Add topics to RDF/RSS 2' );
is($dom->find('link[rel="self"][href="http://sojolicio.us/blog"]')->size,
   2, 'Add topics to RDF/RSS 3' );

# find topics in rss
$dom = $dom->parse($rss);
my $topics = Mojolicious::Plugin::PubSubHubbub::_find_topics('rss',$dom);
is(@$topics, 2, 'Topics in RSS');
ok($topics ~~ ['http://sojolicio.us/2/blog','http://sojolicio.us/blog.rss'],
   'Topics in RSS 2');

# filter topics in rss
$topics = Mojolicious::Plugin::PubSubHubbub::_filter_topics(
  $dom, ['http://sojolicio.us/2/blog'] );
is($dom->find('item')->size, 1, 'Filtered topics in RSS');
is(@$topics, 1, 'Filtered topics in RSS 2');
ok($topics ~~ ['http://sojolicio.us/2/blog'],
   'Filtered topics in RSS 3');
is($dom->find('item')->size, 1, 'Filtered topics in RSS 4');



# find topics in atom
$dom = $dom->parse($atom);
$topics = Mojolicious::Plugin::PubSubHubbub::_find_topics('atom',$dom);
is(@$topics, 2, 'Topics in Atom');
ok($topics ~~ ['http://sojolicio.us/2/blog','http://sojolicio.us/blog.atom'],
   'Topics in Atom 2');

# filter topics in atom
$topics = Mojolicious::Plugin::PubSubHubbub::_filter_topics(
  $dom, ['http://sojolicio.us/2/blog'] );
is($dom->find('entry')->size, 1, 'Filtered topics in Atom');
is(@$topics, 1, 'Filtered topics in Atom 2');
ok($topics ~~ ['http://sojolicio.us/2/blog'],
   'Filtered topics in Atom 3');
is($dom->find('entry')->size, 1, 'Filtered topics in Atom 4');



# find topics in rdf
$dom = $dom->parse($rdf);
$topics = Mojolicious::Plugin::PubSubHubbub::_find_topics('rss',$dom);
is(@$topics, 2, 'Topics in RDF/RSS');
ok($topics ~~ ['http://sojolicio.us/2/blog','http://sojolicio.us/blog.rss'],
   'Topics in RDF/RSS 2');

# filter topics in rdf
$topics = Mojolicious::Plugin::PubSubHubbub::_filter_topics(
  $dom, ['http://sojolicio.us/2/blog'] );
is($dom->find('item')->size, 1, 'Filtered topics in RDF/RSS');
is(@$topics, 1, 'Filtered topics in RDF/RSS 2');
ok($topics ~~ ['http://sojolicio.us/2/blog'],
   'Filtered topics in RDF/RSS 3');
is($dom->find('item')->size, 1, 'Filtered topics in RDF/RSS 4');


my $t = Test::Mojo->new;
$t->test_server;
my $app = $t->app;


$app->plugin('PubSubHubbub', { hub => '/hub'});


$app->routes->route('/push')->pubsub('cb');

$t->get_ok('/push')
  ->content_type_like(qr{^text/html})
  ->status_is(400)
  ->text_like('p:nth-of-type(2)' => qr/not correct/);

# content - fail
$t->post_ok('/push' => $rss)
  ->content_type_like(qr{^text/html})
  ->status_is(400)
  ->text_like('p:nth-of-type(2)' => qr/not correct/);

# Hooks:
my $request_count = 1;

$app->hook(
  'on_pubsub_acceptance' => sub {
    my ($plugin, $c, $type,
	$topics, $secret, $on_behalf) = @_;

    # first request
    if ($request_count == 1) {
      is($type, 'rss', 'on_ps_a (0) - RSS type');
      is(@$topics, 2, "on_ps_a (0) - Topics in RSS");
      ok($topics ~~ ['http://sojolicio.us/2/blog',
		     'http://sojolicio.us/blog.rss'],
	 "on_ps_a (0) - Topics in RSS 2");
    }

    # Second request
    elsif ($request_count == 2) {
      is(@$topics, 2, "on_ps_a ($request_count) - Topics in RSS/Atom/RDF");
      ok($topics ~~ ['http://sojolicio.us/2/blog',
		     'http://sojolicio.us/blog.rss'] ||
         $topics ~~ ['http://sojolicio.us/2/blog',
                     'http://sojolicio.us/blog.atom'],
	 "on_ps_a ($request_count) - Topics in RSS/Atom/RDF 2");
      @$topics = ('http://sojolicio.us/2/blog');
    }

    # Third request
    elsif ($request_count ~~ [3,4,5]) {
      @$topics = ('http://sojolicio.us/2/blog');
      $$secret = 'zoidberg';
    }

    # Fourth request
    elsif ($request_count == 4) {
      @$topics = ('http://sojolicio.us/2/blog');
      $$secret = 'zoidberg';
    };
  });

$app->hook(
  'on_pubsub_content' => sub {
    my ($plugin, $c, $type, $dom) = @_;

    if ($request_count == 1) {
      is($type, 'rss', 'on_ps_c (0) - RSS type');
      is($dom->find('item')->size, 3, 'on_ps_c (0) - RSS size');
      is($dom->find('item > source > link[rel="self"][href]')->size, 3,
	 'on_ps_c (0) - RSS source link size');
    } elsif ($request_count == 2) {
      is($dom->find('item, entry')->size, 1,
	 "on_ps_c ($request_count) - RSS/Atom/RDF size");
      is($dom->find('source > link[rel="self"][href]')->size, 1,
	 "on_ps_c ($request_count) - RSS/Atom/RDF source link size");
    } elsif ($request_count == 3) {
      is(0,1,'Accept content although secret is wrong!')
    } elsif ($request_count == 4) {
      is(1,1,'Accept content with correct secret')
    } elsif ($request_count == 5) {
      is(0,1,'Accept content although secret is wrong!')
    };
  });


# content - with content-type
$t->post_ok('/push' => {'Content-Type' => 'application/rss+xml'} => $rss)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# Next request
$request_count++;

# content - RSS
$t->post_ok('/push' => {'Content-Type' => 'application/rss+xml'} => $rss)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# content - Atom
$t->post_ok('/push' => {'Content-Type' => 'application/atom+xml'} => $atom)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# content - RDF
$t->post_ok('/push' => {'Content-Type' => 'application/rdf+xml'} => $rdf)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# Next request
$request_count++;

# Should not be accepted
$t->post_ok('/push' => {'Content-Type' => 'application/atom+xml'} => $atom)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# Next request
$request_count++;

# Should be accepted
# sig is b($atom)->hmac_sha1_sum('zoidberg');
$t->post_ok('/push' => {'Content-Type' => 'application/atom+xml',
		       'X-Hub-Signature' =>
			 'sha1=420decf37ab162712ab2cc9089277b1c61d41665'}
	     => $atom)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');

# Next request
$request_count++;

# Should not be accepted
$t->post_ok('/push' => {'Content-Type' => 'application/atom+xml',
		       'X-Hub-Signature' =>
			 'sha1=xxx'}
	     => $atom)
  ->content_type_like(qr{^text/plain})
  ->status_is(204)
  ->header_is('Content-Length' => '0');


# Test subscribing
$request_count = 1;

$app->routes->route('/hub')
  ->to(
    cb => sub {
      my $c = shift;

      # First request
      if ($request_count == 1) {
	is ($c->param('hub.mode'), 'subscribe', 'Subscription mode');

	is ($c->param('hub.topic'),
	    'http://sojolicio.us/blog.xml',
	    'Topic correct');

	like($c->param('hub.verify_token'),
	     qr{^[A-za-z0-9]{12}$},
	     'Verify_token correct');

	like($c->param('hub.callback'), qr{/push$}, 'Correct callback');

	is($c->req->headers->header('Content-Type'),
	   'application/x-www-form-urlencoded', 'Content-Type');

	return $c->render_text('okay');
      }

      # Second request
      elsif ($request_count == 2) {
	is ($c->param('hub.mode'), 'subscribe', 'Subscription mode');

	isnt ($c->param('hub.topic'),
	      'http://sojolicio.us/blog.xml',
	      'Topic correct');

	return $c->render_text('not_okay', status => 404);
      }

      # Third request
      elsif ($request_count == 3) {
	is ($c->param('hub.mode'), 'unsubscribe', 'Unsubscription mode');

	is ($c->param('hub.topic'),
	    'http://sojolicio.us/blog.xml',
	    'Topic correct');

	like($c->param('hub.verify_token'),
	     qr{^[A-za-z0-9]{12}$},
	     'Verify_token correct');

	like($c->param('hub.callback'), qr{/push$}, 'Correct callback');

	is($c->req->headers->header('Content-Type'),
	   'application/x-www-form-urlencoded', 'Content-Type');

	return $c->render_text('okay');
      }

      # Second request
      elsif ($request_count == 4) {
	is ($c->param('hub.mode'), 'unsubscribe', 'Unsubscription mode');

	isnt ($c->param('hub.topic'),
	      'http://sojolicio.us/blog.xml',
	      'Topic correct');

	return $c->render_text('not_okay', status => 404);

      }

      elsif ($request_count >= 5) {
	is ($c->param('hub.mode'), 'publish', 'publication mode');
	my @topics = $c->param('hub.url');
	my $test = join(',',@topics);

	if ($request_count == 5) {
	  if ($test eq 'http://sojolicio.us/blog.xml') {
	    return $c->render_text('okay');
	  };
	}

	elsif ($request_count == 6) {
	  if ($test eq '/blog.xml,/comments.xml') {
	    return $c->render_text('okay');
	  };
	};
      };

      return $c->render_not_found;

    });

$app->hook(
  'before_pubsub_subscribe' => sub {
    my ($plugin, $c, $params, $post) = @_;

    if ($request_count == 1) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog.xml', 'Topic to subscribe');
    };
  });

$app->hook(
  'after_pubsub_subscribe' => sub {
    my ($plugin, $c, $params, $code, $body) = @_;

    # First request
    if ($request_count == 1) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog.xml', 'Topic to subscribe');
      is($body, 'okay', 'Response body');
    }

    # Second request
    elsif ($request_count == 2) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog/unknown.xml', 'Topic to subscribe');
      is($body, 'not_okay', 'Response body');
    };
  });

$app->hook(
  'before_pubsub_unsubscribe' => sub {
    my ($plugin, $c, $params, $post) = @_;

    if ($request_count == 3) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog.xml', 'Topic to unsubscribe');
    };
  }
);

$app->hook(
  'after_pubsub_unsubscribe' => sub {
    my ($plugin, $c, $params, $code, $body) = @_;

    # Third request
    if ($request_count == 3) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog.xml', 'Topic to unsubscribe');
      is($body, 'okay', 'Response body');
    }

    # Second request
    elsif ($request_count == 4) {
      my $topic = $params->{topic};
      is($topic, 'http://sojolicio.us/blog/unknown.xml', 'Topic to subscribe');
      is($body, 'not_okay', 'Response body');
    };
  });

ok(!$app->pubsub_subscribe, 'Subscription empty');
ok(!$app->pubsub_subscribe(topic => 'http://sojolicio.us/'),
   'Subscription invalid');
ok(!$app->pubsub_subscribe(hub => '/hub'),
   'Subscription invalid');
ok(!$app->pubsub_subscribe(
  topic => 'sojolicio.us',
  hub => '/hub'),
   'Subscription invalid');
ok($app->pubsub_subscribe(
  topic => 'http://sojolicio.us/blog.xml',
  hub   => '/hub'
), 'Subscribe');

$request_count++;

ok(
  !$app->pubsub_subscribe(
    topic => 'http://sojolicio.us/blog/unknown.xml',
    hub   => '/hub'
  ), 'Subscribe');

$request_count++;

ok($app->pubsub_unsubscribe(
  topic => 'http://sojolicio.us/blog.xml',
  hub   => '/hub'
), 'Unsubscribe');

$request_count++;

ok(
  !$app->pubsub_unsubscribe(
    topic => 'http://sojolicio.us/blog/unknown.xml',
    hub   => '/hub'
  ), 'Unsubscribe');

$request_count = 1;

$t->get_ok('/push?hub.mode=subscribe')
  ->content_type_like(qr{^text/html})
  ->status_is(404);
$t->get_ok('/push?hub.mode=subscribe&hub.topic=http://sojolicio.us/blog.xml')
  ->content_type_like(qr{^text/html})
  ->status_is(404);
$t->get_ok('/push?hub.mode=subscribe&hub.challenge=4567')
  ->content_type_like(qr{^text/html})
  ->status_is(404);
$t->get_ok('/push?hub.mode=foobar&hub.topic=http://sojolicio.us/blog.xml'.
	     '&hub.challenge=4567')
  ->content_type_like(qr{^text/html})
  ->status_is(404);
$t->post_form_ok('/push' => { 'hub.mode' => 'foobar',
			      'hub.topic' => 'http://sojolicio.us/blog.xml',
			      'hub.challenge' => 4567 })
  ->content_type_like(qr{^text/html})
  ->status_is(404);

$app->hook(
  'on_pubsub_verification' => sub {
    my ($plugin, $c, $params, $ok) = @_;

    my $topic = $params->{topic};
    is($topic, 'http://sojolicio.us/blog.xml', 'Topic to verify subscription');

    if ($request_count == 2) {
      $$ok = 1;
    };
  });

$t->post_form_ok('/push' => { 'hub.mode' => 'subscribe',
			      'hub.topic' => 'http://sojolicio.us/blog.xml',
			      'hub.challenge' => 4567 })
  ->content_type_like(qr{^text/html})
  ->status_is(404);

$request_count = 2;

$t->post_form_ok('/push' => { 'hub.mode' => 'subscribe',
			      'hub.topic' => 'http://sojolicio.us/blog.xml',
			      'hub.challenge' => 4567 })
  ->content_type_like(qr{^text/plain})
  ->status_is(200)
  ->content_is(4567);

$request_count = 1;

$t->post_form_ok('/push' => { 'hub.mode' => 'unsubscribe',
			      'hub.topic' => 'http://sojolicio.us/blog.xml',
			      'hub.challenge' => 4567 })
  ->content_type_like(qr{^text/html})
  ->status_is(404);

$request_count = 2;

$t->post_form_ok('/push' => { 'hub.mode' => 'unsubscribe',
			      'hub.topic' => 'http://sojolicio.us/blog.xml',
			      'hub.challenge' => 4567 })
  ->content_type_like(qr{^text/plain})
  ->status_is(200)
  ->content_is(4567);

$request_count = 5;

# Publish
ok(!$app->pubsub_publish, 'Publication empty');
ok($app->pubsub_publish('http://sojolicio.us/blog.xml'),
   'Publication set');

$request_count = 6;

$app->routes->route('/blog.xml')->name('blog_route');
$app->routes->route('/comments.xml')->endpoint('comment_route');

ok($app->pubsub_publish('blog_route','comment_route'),
   'Publication set');





# Todo: <channel><item><source url="" /></item></channel>
# Todo: https://bitbucket.org/pstatic/pubsubhubbub/src/f650addc29aa/test_pubsubhubbub.py

BEGIN {
  our $rss =<<'EORSS';
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>My Blog</title>
    <link>http://sojolicio.us/blog</link>
    <atom10:link type="application/rss+xml"
                 href="http://sojolicio.us/blog.rss"
                 xmlns:atom10="http://www.w3.org/2005/Atom"
                 rel="self" />
    <description>Blog for Sojolicious</description>
    <language>en</language>
    <lastBuildDate>Sun, 02 Oct 2011 15:17:30 PDT</lastBuildDate>
    <generator>http://sojolicio.us/</generator>
    <atom10:link href="http://pubsubhubbub.appspot.com/"
                 xmlns:atom10="http://www.w3.org/2005/Atom"
                 rel="hub"/>
    <image>
      <link>http://sojolicio.us</link>
      <url>http://sojolicio.us/favicon.ico</url>
      <title>Sojolicious</title>
    </image>
    <item>
      <title>First Post</title>
      <link>http://sojolicio.us/blog/first_post.html</link>
      <category>Post</category>
      <category>sojolicious</category>
      <dc:creator xmlns:dc="http://purl.org/dc/elements/1.1/">Akron</dc:creator>
      <pubDate>Sun, 02 Oct 2011 15:15:50 PDT</pubDate>
      <guid isPermaLink="false">http://sojolicio.us/blog/1</guid>
      <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">&lt;p&gt; &lt;em&gt;My first blog post&lt;/em&gt; - content</content:encoded>
      <description>My first blog post - description</description>
    </item>
    <item xml:id="second_item">
      <source xmlns="http://www.w3.org/2005/Atom" />
    </item>
    <item xml:id="third_item">
      <source xmlns="http://www.w3.org/2005/Atom">
        <link rel="self" href="http://sojolicio.us/2/blog" />
      </source>
    </item>
  </channel>
</rss>
EORSS

  our $atom =<<'EOATOM';
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>http://sojolicio.us/blog.atom</id>
  <title>My Blog</title>
  <subtitle>Blog about sojolicious</subtitle>
  <updated>2011-10-06T14:00:13+00:00</updated>
  <author>
    <uri>acct:akron@sojolicio.us</uri>
    <name>Akron</name>
    <link rel="alternate" type="text/html" href="http://sojolicio.us/akron"/>
  </author>
  <link href="http://sojolicio.us/blog"
        rel="alternate"
        type="text/html"/>
  <link href="http://pubsubhubbub.appspot.com/"
        rel="hub"/>
  <link href="http://sojolicio.us/blog.atom"
        rel="self"
        type="application/atom+xml"/>
  <entry>
    <id>http://sojolicio.us/blog/1</id>
    <title>first post</title>
    <content type="html">This is my first post</content>
    <link rel="alternate"
          type="text/html"
          href="http://blog/1"/>
    <published>2011-10-06T14:00:11+00:00</published>
    <updated>2011-10-06T14:00:11+00:00</updated>
    <link rel="self"
          type="application/atom+xml"
          href="http://sojolicio.us/blog/1.atom"/>
  </entry>
  <entry xml:id="second_item">
    <source xmlns="http://www.w3.org/2005/Atom" />
  </entry>
  <entry xml:id="third_item">
    <source xmlns="http://www.w3.org/2005/Atom">
      <link rel="self" href="http://sojolicio.us/2/blog" />
    </source>
  </entry>
</feed>
EOATOM

our $rdf =<< 'EORDF';
<?xml version="1.0" encoding="utf-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns="http://purl.org/rss/1.0/">
  <channel rdf:about="http://sojolicio.us/blog">
    <title>Blog about Sojolicious</title>
    <link>http://sojolicio.us/blog</link>
    <atom10:link type="application/rdf+xml"
                 href="http://sojolicio.us/blog.rss"
                 xmlns:atom10="http://www.w3.org/2005/Atom"
                 rel="self"/>
    <description/>
    <atom10:link href="http://pubsubhubbub.appspot.com/"
                 xmlns:atom10="http://www.w3.org/2005/Atom"
                 rel="hub"/>
    <items>
      <rdf:Seq>
        <rdf:li rdf:resource="tag:blogger.com,1999:blog-001.post-001a"/>
        <rdf:li rdf:resource="tag:blogger.com,1999:blog-002.post-002b"/>
        <rdf:li rdf:resource="tag:blogger.com,1999:blog-003.post-003b"/>
      </rdf:Seq>
    </items>
  </channel>
  <item rdf:about="tag:blogger.com,1999:blog-001.post-001a">
    <title>My Blog</title>
    <link>http://sojolicio.us/blog/1</link>
    <dc:creator>akron@sojolicio.us (Akron)</dc:creator>
    <dc:date>2011-10-04T03:03:49-07:00</dc:date>
    <description>My first blog post - description</description>
  </item>
  <item xml:id="second_item">
    <source xmlns="http://www.w3.org/2005/Atom" />
  </item>
  <item xml:id="third_item">
    <source xmlns="http://www.w3.org/2005/Atom">
      <link rel="self" href="http://sojolicio.us/2/blog" />
    </source>
  </item>
</rdf:RDF>
EORDF

};

__END__
