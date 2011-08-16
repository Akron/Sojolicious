#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Test::More tests => 1;
use Test::Mojo;

ok('Mojolicious::Plugin::HostMeta');
