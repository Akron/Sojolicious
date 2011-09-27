#!/usr/bin/perl

use Test::More tests => 1;

use lib '../lib';

use_ok('Mojolicious::Plugin::Atom');

my $atom = Mojolicious::Plugin::Atom::Document->new('entry');
$atom->add_extension('Mojolicious::Plugin::Atom::Threading');

$atom->add_author(name => 'Peter');
$atom->add_replies_link({count => 4});

# diag $atom->to_pretty_xml;
