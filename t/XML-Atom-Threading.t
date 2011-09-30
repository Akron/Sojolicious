#!/usr/bin/perl

use lib '../lib';

use Test::More tests => 15;
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('XML' => {
  new_atom => ['Atom','Atom::Threading']
});

my $entry = $app->new_atom('entry');

is($entry->at(':root')->namespace, 'http://www.w3.org/2005/Atom', 'Namespace');

my $person = $entry->new_person(name => 'Zoidberg');

$entry->add_author($person);

is($entry->at('entry > author > name')->text, 'Zoidberg', 'Name');

$entry->add_contributor($person);

is($entry->at('entry > contributor > name')->text, 'Zoidberg', 'Name');

$entry->add_id('http://sojolicio.us/blog/2');

is($entry->at('entry')->attrs->{'xml:id'}, 'http://sojolicio.us/blog/2', 'id');
is($entry->at('entry id')->text, 'http://sojolicio.us/blog/2', 'id');

$entry->add_replies_link( 'http://sojolicio.us/entry/1/replies',
			 { count => 5,
			   updated => $entry->new_date(5000) });

my $link = $entry->at('link[rel="replies"]');
is($link->attrs('thr:count'), 5, 'Thread Count');
is($link->attrs('thr:updated'), '1970-01-01T01:23:20Z', 'Thread update');
is($link->attrs('href'), 'http://sojolicio.us/entry/1/replies', 'Thread href');
is($link->attrs('type'), 'application/atom+xml', 'Thread type');
is($link->namespace, 'http://www.w3.org/2005/Atom', 'Thread namespace');

$entry->add_total(8);

is($entry->at('total')->text, 8, 'Total number');
is($entry->at('total')->namespace , 'http://purl.org/syndication/thread/1.0', 'Total namespace');

$entry->add_in_reply_to( 'http://sojolicio.us/blog/1',
			 { href => 'http://sojolicio.us/blog/1x'} );

is($entry->at('in-reply-to')->namespace,
   'http://purl.org/syndication/thread/1.0', 'In-reply-to namespace');

is($entry->at('in-reply-to')->attrs('href'),
   'http://sojolicio.us/blog/1x', 'In-reply-to href');

is($entry->at('in-reply-to')->attrs('ref'),
   'http://sojolicio.us/blog/1', 'In-reply-to ref');

__END__
