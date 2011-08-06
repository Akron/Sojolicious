#!/usr/bin/perl
use strict;
use warnings;

$|++;

use lib '../lib';

use Mojo::ByteStream 'b';
use Test::Mojo;
use Mojolicious::Lite;

use Test::More tests => 1;

use_ok('Mojolicious::Plugin::ActivityStreams');

__END__

my $as = Mojolicious::Plugin::ActivityStreams::Document->new('feed');

diag $as->to_pretty_xml;
