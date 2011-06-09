#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 8;
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('host_meta' =>
	     { host => 'sojolicio.us', secure => 1 });

# Silence
$app->log->level('error');

$app->hook('before_serving_hostmeta' => sub {
    my ($c, $xrd) = @_;
    $xrd->add('Property', { type => 'foo' }, 'bar');
    is($c->endpoint('hostmeta'), 'https://sojolicio.us/.well-known/host-meta',
       'Correct url');
	   });

my $xrd_test = $t->get_ok('/.well-known/host-meta')->status_is(200);

$xrd_test->element_exists('Host')->text_is('sojolicio.us');
$xrd_test->element_exists('Property[type="foo"]')->text_is('bar');

$app->hook('before_fetching_hostmeta',
	   => sub {
	       my ($c, $host, $xrd_ref) = @_;

	       if ($host eq 'example.org') {

		   my $xrd = $c->new_xrd;

		   my $sub = $xrd->add('Link', { rel => 'bar' }, 'foo' );
		   $sub->comment('New Link');
		   $$xrd_ref = $xrd;
	       }
	   });

my $xrd = $t->app->hostmeta('example.org');
is($xrd->get_link('bar')->text, 'foo', 'Correct link');

