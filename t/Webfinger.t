#!/usr/bin/env perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 15;
use Test::Mojo;
use Mojo::ByteStream 'b';
use Mojolicious::Lite;

my $t = Test::Mojo->new;
my $app = $t->app;
$app->plugin('webfinger');
my $c = Mojolicious::Controller->new;
$c->app($app);

my $webfinger_host = 'webfing.er';
my $acct = 'acct:akron@webfing.er';

# Rewrite req-url
$c->req->url->parse('http://'.$webfinger_host);
$app->hook(
  before_dispatch => sub {
    for (shift->req->url) {
      $_->host($webfinger_host);
      $_->scheme('http');
    }
  });

$app->routes->route('/webfinger')->lrdd('q');

is($c->hostmeta->get_link('lrdd')->attrs->{template},
   'http://'.$webfinger_host.'/webfinger?q={uri}',
   'Correct uri');

is ($c->endpoint('lrdd' => {uri => $acct}),
    'http://'.$webfinger_host.'/webfinger?q='.b($acct)->url_escape,
    'Webfinger endpoint');

app->hook(
  'on_prepare_webfinger' =>
    sub {
      my ($plugin, $c, $wf, $ok_ref) = @_;
      if ($wf eq $acct) {
	$$ok_ref = 1;
      };
    });

$app->hook(
  'before_serving_webfinger' =>
    sub {
      my ($plugin, $c, $norm, $xrd) = @_;
      if ($norm eq $acct) {
	$xrd->add_link( 'http://microformats.org/profile/hcard',
			{   type => 'text/html',
			    href => 'http://sojolicio.us/akron.hcard' });
	$xrd->add_link('describedby',
		       {   type => 'application/rdf+xml',
			   href => 'http://sojolicio.us/akron.foaf' });
      } else {
	$xrd = undef;
      };
    });

my $wf = $c->webfinger($acct);

ok($wf, 'Webfinger');
is($wf->at('Subject')->text, $acct, 'Subject');
is($wf->get_link('http://microformats.org/profile/hcard')
   ->attrs('href'), 'http://sojolicio.us/akron.hcard',
                    'Webfinger-hcard');
is($wf->get_link('http://microformats.org/profile/hcard')
   ->attrs('type'), 'text/html',
                    'Webfinger-hcard-type');
is($wf->get_link('describedby')
   ->attrs('href'), 'http://sojolicio.us/akron.foaf',
                    'Webfinger-described_by');
is($wf->get_link('describedby')
   ->attrs('type'), 'application/rdf+xml',
                    'Webfinger-descrybed_by-type');


$t->get_ok('/webfinger?q='.b($acct)->url_escape)
  ->status_is('200')
  ->content_type_is('application/xrd+xml')
  ->text_is('Subject' => $acct);

$t->get_ok('/webfinger?q=nothing')
  ->status_is('404')
  ->content_type_like(qr/html/);


__END__
