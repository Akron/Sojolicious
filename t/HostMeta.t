#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 42;
use Test::Mojo;
use Mojolicious::Lite;


my $hm_host = 'hostme.ta';

my $t = Test::Mojo->new;
my $app = $t->app;
$app->plugin('HostMeta');

my $c = Mojolicious::Controller->new;
$c->app($app);
$c->req->url->parse('http://' . $hm_host);
$app->hook(
  before_dispatch => sub {
    for (shift->req->url) {
      $_->host($hm_host);
      $_->scheme('http');
    }
  });


my $h = $app->renderer->helpers;

# XRD
ok($h->{new_xrd}, 'render_xrd fine.');
ok($h->{render_xrd}, 'render_xrd fine.');

# Util::Endpoint
ok($h->{endpoint}, 'endpoint fine.');

# Hostmeta
ok($h->{hostmeta}, 'hostmeta fine.');

# Reverse check
ok(!exists $h->{foobar}, 'foobar not fine.');

$t->get_ok('/.well-known/host-meta')
    ->status_is(200)
    ->content_type_is('application/xrd+xml')
    ->element_exists('XRD')
    ->element_exists('XRD[xmlns]')
    ->element_exists('XRD[xsi]')
    ->element_exists_not('Link')
    ->element_exists_not('Property')
    ->element_exists('Host')->text_is($hm_host);

$app->hook(
  'before_serving_hostmeta' => sub {
    my ($plugin, $c, $xrd) = @_;
    $xrd->add('Property', { type => 'foo' }, 'bar');
    is($c->endpoint('hostmeta'),
       'http://'.$hm_host.'/.well-known/host-meta', 'Correct url');
  });

$t->get_ok('/.well-known/host-meta')
    ->status_is(200)
    ->content_type_is('application/xrd+xml')
    ->element_exists('XRD')
    ->element_exists('XRD[xmlns]')
    ->element_exists('XRD[xsi]')
    ->element_exists_not('Link')
    ->element_exists('Property')
    ->element_exists('Property[type="foo"]')
    ->text_is('bar')
    ->element_exists('Host')->text_is($hm_host);

$app->hook('before_fetching_hostmeta',
	   => sub {
	     my ($plugin, $c, $host, $xrd_ref) = @_;

	     if ($host eq 'example.org') {
	       my $xrd = $c->new_xrd;
	       my $sublink = $xrd->add('Link', { rel => 'bar' }, 'foo' );
	       $$xrd_ref = $xrd;
	     }
	   });

my $xrd = $t->app->hostmeta('example.org');
ok(!$xrd->get_property, 'Property not found.');
ok(!$xrd->get_property('bar'), 'Property not found.');
is($xrd->at('Link')->attrs('rel'), 'bar', 'Correct link');
ok(!$xrd->get_link, 'Empty Link request');
is($xrd->get_link('bar')->text, 'foo', 'Correct link');

my ($test1, $test2) = (1,1);
$app->hook('on_prepare_hostmeta',
	   => sub {
	     my ($plugin, $c, $xrd_ref) = @_;

	     $xrd_ref->add_property('permanentcheck' => $test1++ );
	   });

$app->hook('before_serving_hostmeta',
	   => sub {
	     my ($plugin, $c, $xrd_ref) = @_;

	     $xrd_ref->add_property('check' => $test2++ );
	   });

$xrd = $c->hostmeta;
is($xrd->get_property('permanentcheck')->text, 1, 'on_prepare_hostmeta 1');
is($xrd->get_property('check')->text, 1, 'before_serving_hostmeta 1');

$xrd = $c->hostmeta;
is($xrd->get_property('permanentcheck')->text, 1, 'on_prepare_hostmeta 2');
is($xrd->get_property('check')->text, 2, 'before_serving_hostmeta 2');

$xrd = $c->hostmeta;
is($xrd->get_property('permanentcheck')->text, 1, 'on_prepare_hostmeta 3');
is($xrd->get_property('check')->text, 3, 'before_serving_hostmeta 3');
