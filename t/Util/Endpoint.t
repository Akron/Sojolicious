#!/usr/bin/env perl
use strict;
use warnings;

$|++;

use lib '../../lib';

use Test::More tests => 23;
use Test::Mojo;

use Mojolicious::Lite;
use Mojo::ByteStream 'b';

my $t = Test::Mojo->new;
my $app = $t->app;

$app->plugin('Util::Endpoint');

my $endpoint_host = 'endpoi.nt';

# Set endpoint
my $r_test = $app->routes->route('/test');
$r_test->endpoint('test1' =>
		    {
		      host   => $endpoint_host,
		      scheme => 'https'
		    });

is($app->endpoint('test1'),
   "https://$endpoint_host/test",
   'endpoint 1');

$r_test->endpoint(test2 => {
    host => $endpoint_host,
    scheme => 'https',
    query => [ a => '{var1}'] });

is($app->endpoint('test2'),
   'https://'.$endpoint_host.'/test?a={var1}',
   'endpoint 2');

is($app->endpoint('test2', {var1 => 'b'}),
   'https://'.$endpoint_host.'/test?a=b',
   'endpoint 3');

$r_test->endpoint(test3 => {
  host => $endpoint_host,
  query => [ a => '{var1}',
	     b => '{var2}'
	   ]});

is($app->endpoint('test3', {var1 => 'b'}),
   'http://'.$endpoint_host.'/test?a=b&b={var2}',
   'endpoint 4');

is($app->endpoint('test3', {var2 => 'd'}),
   'http://'.$endpoint_host.'/test?a={var1}&b=d',
   'endpoint 5');

is($app->endpoint('test3', {var1 => 'c', var2 => 'd'}),
   'http://'.$endpoint_host.'/test?a=c&b=d',
   'endpoint 6');

$r_test = $app->routes->route('/suggest');
$r_test->endpoint(test4 => {
		      host => $endpoint_host,
		      query => [ q => '{searchTerms}',
		                 start => '{startIndex?}'
			  ]});

is($app->endpoint('test4'),
   'http://'.$endpoint_host.'/suggest?q={searchTerms}&start={startIndex?}',
   'endpoint 7');

is($app->endpoint('test4' => { searchTerms => 'simpsons'}),
   'http://'.$endpoint_host.'/suggest?q=simpsons&start={startIndex?}',
   'endpoint 8');

is($app->endpoint('test4' => { startIndex => 4}),
   'http://'.$endpoint_host.'/suggest?q={searchTerms}&start=4',
   'endpoint 9');

is($app->endpoint('test4' => {
                     searchTerms => 'simpsons',
                     '?' => undef
                  }),
   'http://'.$endpoint_host.'/suggest?q=simpsons',
   'endpoint 10');

my $acct    = 'acct:akron@sojolicio.us';
my $btables = 'hmm&bobby=tables';
is($app->endpoint('test4' => {
                     searchTerms => $acct,
                     startIndex => $btables
                  }),
   'http://'.$endpoint_host.'/suggest?' . 
   'q=' . b($acct)->url_escape . 
   '&start=' . b($btables)->url_escape,
   'endpoint 11');

$r_test->endpoint(test5 => {
    query => [ a => '{foo?}',
	       b => '{bar?}',
	       c => '{foo}',
	       d => '{BAR}'
	]});

is($app->endpoint('test5' =>
		  {
		      bar => 'This is a {test}'
		  }),
   '/suggest?a={foo?}&b=This%20is%20a%20%7Btest%7D&c={foo}&d={BAR}',
   'endpoint 12');

is($app->endpoint('test5' =>
		  {
		      BAR => '?'
		  }),
   '/suggest?a={foo?}&b={bar?}&c={foo}&d=%3F',
   'endpoint 13');

is($app->endpoint('test5' =>
		  {
		      bar => '}&{'
		  }),
   '/suggest?a={foo?}&b=%7D%26%7B&c={foo}&d={BAR}',
   'endpoint 14');

is($app->endpoint('test5' =>
		  {
		      '?' => undef
		  }),
   '/suggest?c={foo}&d={BAR}',
   'endpoint 15');

$r_test->endpoint(test6 => {
    query => [ a => '{foo?}',
	       b => '{bar?}',
	       c => '{foo}',
	       d => '{BAR}',
	       e => '{test:foo?}',
	       f => '*'
	]});

is($app->endpoint('test6' =>
		  {
		      '?' => undef
		  }),
   '/suggest?c={foo}&d={BAR}&f=*',
   'endpoint 16');

is($app->endpoint('test6' =>
		  {
		      'test:foo' => 'check',
		      '?' => undef
		  }),
   '/suggest?c={foo}&d={BAR}&e=check&f=*',
   'endpoint 17');

my $hash = $app->get_endpoints;

is ($hash->{test1},
    'https://'.$endpoint_host.'/test',
    'hash-test 1');

is ($hash->{test2},
    'https://'.$endpoint_host.'/test?a={var1}',
    'hash-test 2');

is ($hash->{test3},
    'http://'.$endpoint_host.'/test?a={var1}&b={var2}',
    'hash-test 3');

is ($hash->{test4},
    'http://'.$endpoint_host.'/suggest?q={searchTerms}&start={startIndex?}',
    'hash-test 4');

is ($hash->{test5},
    '/suggest?a={foo?}&b={bar?}&c={foo}&d={BAR}',
    'hash-test 5');

is ($hash->{test6},
    '/suggest?a={foo?}&b={bar?}&c={foo}&d={BAR}&e={test:foo?}&f=*',
    'hash-test 6');
