#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Test::More tests => 15;

use_ok('Mojolicious::Plugin::XML::Atom');

# new
my $as = Mojolicious::Plugin::XML::Atom->new('feed');
$as->add_extension('Mojolicious::Plugin::XML::ActivityStreams');

is(ref($as), 'Mojolicious::Plugin::XML::Atom', 'new 1');
my $as_entry = Mojolicious::Plugin::XML::Atom->new('entry');
is(ref($as), 'Mojolicious::Plugin::XML::Atom', 'new 2');


# add author
$as->add_author(name => 'Fry');
is($as->at('feed > author > name')->text,
   'Fry',
   'Add author 1');
my $person = $as_entry->new_person(name => 'Bender',
				   uri => 'http://sojolicio.us/bender');
$as_entry->add_author($person);
is($as_entry->at('entry > author > name')->text,
   'Bender',
    'Add author 2');
is($as_entry->at('entry > author > uri')->text,
   'http://sojolicio.us/bender',
    'Add author 3');

$as_entry = $as->add_entry($as_entry);


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

__END__
