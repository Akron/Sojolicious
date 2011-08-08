#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Mojo::ByteStream 'b';
use Test::Mojo;
use Mojolicious::Lite;

use Test::More tests => 17;

use_ok('Mojolicious::Plugin::ActivityStreams');



# new
my $as = Mojolicious::Plugin::ActivityStreams->new('feed');
is(ref($as), 'Mojolicious::Plugin::ActivityStreams::Document', 'new 1');
my $as_feed = $as->new_feed;
is(ref($as_feed), 'Mojolicious::Plugin::ActivityStreams::Document', 'new 2');
$as = $as->new_entry;
is(ref($as), 'Mojolicious::Plugin::ActivityStreams::Document', 'new 3');


# add actor
$as_feed->add_actor(name => 'Fry');
is($as_feed->at('feed > author > name')->text,
   'Fry',
   'Add actor 1');
my $person = $as->new_person(name => 'Bender',
		             uri => 'http://sojolicio.us/bender');
$as->add_actor($person);
is($as->at('entry > author > name')->text,
   'Bender',
    'Add actor 2');
is($as->at('entry > author > uri')->text,
   'http://sojolicio.us/bender',
    'Add actor 3');

$as = $as_feed->add_entry($as);


# add verb
$as->add_verb('follow');
is($as->at('verb')->namespace, 'http://activitystrea.ms/schema/1.0/', 'Add verb');

# add object
$as->add_object(type => 'person',
                displayName => 'Leela');
is($as->at('object > displayName')->text, 'Leela', 'Add object 1');
is($as->at('object > object-type')->text,
   'http://activitystrea.ms/schema/1.0/person', 'Add object 2');
is($as->at('object')->namespace,
   'http://activitystrea.ms/schema/1.0/', 'Add object 3');
is($as->at('object > object-type')->namespace,
   'http://activitystrea.ms/schema/1.0/', 'Add object 4');


# add target
$as->add_target(type => 'person',
                displayName => 'Zoidberg');
is($as->at('target > displayName')->text, 'Zoidberg', 'Add target 1');
is($as->at('target > object-type')->text,
   'http://activitystrea.ms/schema/1.0/person', 'Add target 2');
is($as->at('target')->namespace,
   'http://activitystrea.ms/schema/1.0/', 'Add target 3');
is($as->at('target > object-type')->namespace,
   'http://activitystrea.ms/schema/1.0/', 'Add target 4');


# Plugin helper
my $t = Test::Mojo->new;
my $app = $t->app;

$app->plugin('activity_streams');
$as = $app->new_activity;


my $as_string = $as->to_pretty_xml;
$as_string =~ s/[\s\r\n]+//g;

is ($as_string, '<?xmlversion="1.0"encoding="UTF-8'.
                '"standalone="yes"?><feedxmlns="ht'.
                'tp://www.w3.org/2005/Atom"xmlns:a'.
                'ctivity="http://activitystrea.ms/'.
                'schema/1.0/"/>',
                'Initial ActivityStream');


__END__
