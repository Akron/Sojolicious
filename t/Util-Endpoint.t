#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 11;
use Test::Mojo;
use Mojolicious::Lite;
use Mojo::ByteStream 'b';

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

$r_test = $app->routes->route('/suggest');
$r_test->endpoint(test4 => {
		      host => 'sojolicio.us',
		      query => [ q => '{searchTerms}',
		                 start => '{startIndex?}'
			  ]});

is($app->endpoint('test4'),
   'http://sojolicio.us/suggest?q={searchTerms}&start={startIndex?}',
   'endpoint 7');

is($app->endpoint('test4' => { searchTerms => 'simpsons'}),
   'http://sojolicio.us/suggest?q=simpsons&start={startIndex?}',
   'endpoint 8');

is($app->endpoint('test4' => { startIndex => 4}),
   'http://sojolicio.us/suggest?q={searchTerms}&start=4',
   'endpoint 9');

is($app->endpoint('test4' => {
                     searchTerms => 'simpsons',
                     '?' => undef
                  }),
   'http://sojolicio.us/suggest?q=simpsons',
   'endpoint 10');

my $acct    = 'acct:akron@sojolicio.us';
my $btables = 'hmm&bobby=tables';
is($app->endpoint('test4' => {
                     searchTerms => $acct,
                     startIndex => $btables
                  }),
   'http://sojolicio.us/suggest?' . 
   'q=' . b($acct)->url_escape . 
   '&start=' . b($btables)->url_escape,
   'endpoint 11');
