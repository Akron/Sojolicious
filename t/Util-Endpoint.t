#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 6;
use Test::Mojo;
use Mojolicious::Lite;


my $t = Test::Mojo->new;
my $app = $t->app;

$app->plugin('Util::Endpoint');

# Set endpoint
my $r_test = $app->routes->route('/test');
$r_test->endpoint('test1' =>
		  {
		      host => 'sojolicio.us',
		      scheme => 'https'
		  });	

is($app->endpoint('test1'),
   'https://sojolicio.us/test',
   'endpoint 1');

$r_test->endpoint(test2 => {
    host => 'sojolicio.us',
    scheme => 'https',
    query => [ a => '{var1}'] });

is($app->endpoint('test2'),
   'https://sojolicio.us/test?a={var1}',
   'endpoint 2');

is($app->endpoint('test2', {var1 => 'b'}),
   'https://sojolicio.us/test?a=b',
   'endpoint 3');

$r_test->endpoint(test3 => {
		      host => 'sojolicio.us',
			  query => [ a => '{var1}',
				     b => '{var2}'
			  ]});


is($app->endpoint('test3', {var1 => 'b'}),
   'http://sojolicio.us/test?a=b&b={var2}',
   'endpoint 4');

is($app->endpoint('test3', {var2 => 'd'}),
   'http://sojolicio.us/test?a={var1}&b=d',
   'endpoint 5');

is($app->endpoint('test3', {var1 => 'c', var2 => 'd'}),
   'http://sojolicio.us/test?a=c&b=d',
   'endpoint 6');
