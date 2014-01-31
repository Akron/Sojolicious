#!/usr/bin/env perl
use Test::Mojo;
use Test::More tests => 30;
use Mojolicious::Lite;
use strict;
use warnings;

$|++;

use lib '../../lib';

my $t = Test::Mojo->new;

my $app = $t->app;

my $c = Mojolicious::Controller->new;
$c->app($app);

$app->plugin('TagHelpers::Pagination');

my $string = $c->pagination( 4, 15, '#action={page}' );

is(length $string, 215, 'String length');
like($string, qr/^\<a href="#action=3">\&lt;<\/a>\&nbsp;/, 'String begin');
like($string, qr/\<a href="#action=5">\&gt;<\/a>$/, 'String end');
like($string,
     qr/<a href="#action=5">5<\/a>\&nbsp;\.\.\.\&nbsp;<a href="#action=15">15<\/a>/,
     'String ellipsis');
like($string, qr/\[4\]/, 'Current');

$string = $c->pagination( 4, 15, '/page-{page}?page={page}');

like($string, qr/^<a href="\/page-3\?page=3">\&lt;<\/a>/, 'New template');
my $url = Mojo::URL->new('http://sojolicio.us:3000/pages');
$url->query({ page => 'offset-{page}'});

$string = $c->pagination( 4, 15, $url);

like($string,
     qr/^<a href="http:\/\/sojolicio\.us:3000\/pages\?page=offset-3">\&lt;<\/a>/,
     'Pagination with Mojo::URL');

$string = $c->pagination( 2, 3 );
unlike($string, qr/\.\.\./, 'No ellipsis');
is(length $string, 101, 'New pagination string');

$string = $c->pagination(1,1);
is($string, '&lt;&nbsp;[1]&nbsp;&gt;', 'Pagination 1/1');

$string = $c->pagination(1,2);
is($string, '&lt;&nbsp;[1]&nbsp;<a href="2">2</a>'.
     '&nbsp;<a href="2">&gt;</a>',
   'Pagination 1/2');

$string = $c->pagination(2,2);
is($string, '<a href="1">&lt;</a>&nbsp;<a href="1">1</a>'.
     '&nbsp;[2]&nbsp;&gt;',
   'Pagination 2/2');

$string = $c->pagination(1,3);
is($string, '&lt;&nbsp;[1]&nbsp;<a href="2">2</a>&nbsp;'.
     '<a href="3">3</a>&nbsp;<a href="2">&gt;</a>',
   'Pagination 1/3');

$string = $c->pagination(2,3);
is($string, '<a href="1">&lt;</a>&nbsp;<a href="1">1</a>&nbsp;'.
     '[2]&nbsp;<a href="3">3</a>&nbsp;<a href="3">&gt;</a>',
   'Pagination 2/3');

$string = $c->pagination(3,3);
is($string, '<a href="2">&lt;</a>&nbsp;<a href="1">1</a>&nbsp;'.
     '<a href="2">2</a>&nbsp;[3]&nbsp;&gt;',
   'Pagination 3/3');

$string = $c->pagination(3,7);
is($string, '<a href="2">&lt;</a>&nbsp;<a href="1">1</a>&nbsp;'.
     '<a href="2">2</a>&nbsp;[3]&nbsp;<a href="4">4</a>&nbsp;'.
       '...&nbsp;<a href="7">7</a>&nbsp;<a href="4">&gt;</a>',
   'Pagination 3/7');

$string = $c->pagination(0,8);
is($string, '&lt;&nbsp;<a href="1">1</a>&nbsp;'.
     '<a href="2">2</a>&nbsp;<a href="3">3</a>&nbsp;'.
       '...&nbsp;<a href="8">8</a>&nbsp;<a href="1">&gt;</a>',
   'Pagination 0/8');

$string = $c->pagination(0,0);
is($string, '', 'Pagination 0/0');

$string = $c->pagination(0,1);
is($string, '&lt;&nbsp;<a href="1">1</a>&nbsp;<a href="1">&gt;</a>',
   'Pagination 0/1');

$string = $c->pagination(0,2);
is($string, '&lt;&nbsp;<a href="1">1</a>&nbsp;<a href="2">2</a>&nbsp;<a href="1">&gt;</a>',
   'Pagination 0/2');

$string = $c->pagination(0,3);
is($string, '&lt;&nbsp;<a href="1">1</a>&nbsp;<a href="2">2</a>&nbsp;<a href="3">3</a>&nbsp;<a href="1">&gt;</a>',
   'Pagination 0/3');

$string = $c->pagination(0,4);
is($string, '&lt;&nbsp;<a href="1">1</a>&nbsp;<a href="2">2</a>&nbsp;<a href="3">3</a>&nbsp;<a href="4">4</a>&nbsp;<a href="1">&gt;</a>',
   'Pagination 0/4');


$string = $c->pagination( 4, 15, '#action={page}' => {
  separator => ' ',
  prev      => '***',
  next      => '+++',
  ellipsis  => '---',
  current   => '<strong>{current}</strong>'
});

like($string, qr/^<a href="#action=3">\*\*\*<\/a> /, 'String begin');
like($string, qr/<a href="#action=5">\+\+\+<\/a>$/, 'String end');
like($string,
     qr/<a href="#action=5">5<\/a> --- <a href="#action=15">15<\/a>/,
     'String ellipsis');
like($string, qr/<strong>4<\/strong>/, 'Current');

$t = Test::Mojo->new;
$app = $t->app;
$c->app($app);

$app->plugin('TagHelpers::Pagination' =>
	       {
		 separator => ' ',
		 prev      => '***',
		 next      => '+++',
		 ellipsis  => '---',
		 current   => '<strong>{current}</strong>'
	       }
	   );

$string = $c->pagination( 4, 15, '#action={page}');

like($string, qr/^<a href="#action=3">\*\*\*<\/a> /, 'String begin');
like($string, qr/<a href="#action=5">\+\+\+<\/a>$/, 'String end');
like($string,
     qr/<a href="#action=5">5<\/a> --- <a href="#action=15">15<\/a>/,
     'String ellipsis');
like($string, qr/<strong>4<\/strong>/, 'Current');
