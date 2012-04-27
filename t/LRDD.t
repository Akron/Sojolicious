#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 20;
use Test::Mojo;
use Mojo::ByteStream 'b';
use Mojolicious::Lite;

my $lrdd_host = 'lr.dd';
my $ressource = 'http://lr.dd/hey';

my $t = Test::Mojo->new;
my $app = $t->app;
$app->plugin('LRDD');

my $c = Mojolicious::Controller->new;
$c->app($app);

# Rewrite req-url
$c->req->url->parse('http://lr.dd');
$app->hook(
  before_dispatch => sub {
    for (shift->req->url) {
      $_->host($lrdd_host);
      $_->scheme('http');
    }
  });

$app->routes->route('/lrdd')->lrdd('q');

is($c->hostmeta->get_link('lrdd')->attrs->{template},
   'http://'.$lrdd_host.'/lrdd?q={uri}',
   'Correct uri');

is ($c->endpoint('lrdd' => {uri => $ressource}),
    'http://'.$lrdd_host.'/lrdd?q='.b($ressource)->url_escape,
    'Correct endpoint');

$app->hook(
  'on_prepare_lrdd' =>
    sub {
      my ($plugin, $c, $lrdd, $ok_ref) = @_;
      if ($lrdd eq $ressource) {
	$$ok_ref = 1;
      };
    });

$app->hook(
  'before_serving_lrdd' =>
    sub {
      my ($plugin, $c, $lrdd, $xrd) = @_;

      if ($lrdd eq $ressource) {
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

my $wf = $c->lrdd($ressource);

ok($wf, 'lrdd');
is($wf->at('Subject')->text, $ressource, 'Subject');
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

$t->get_ok('/lrdd?q='.b($ressource)->url_escape)
  ->status_is('200')
  ->content_type_is('application/xrd+xml')
  ->text_is('Subject' => $ressource);

$t->get_ok('/lrdd?q=akron@sojolicio.us')
  ->status_is('404')
  ->content_type_like(qr/xrd/)
  ->text_is('Subject', 'akron@sojolicio.us');

$t->get_ok('/.well-known/host-meta?resource='.b($ressource)->url_escape)
  ->status_is('200')
  ->content_type_is('application/xrd+xml')
  ->text_is('Subject' => $ressource);
