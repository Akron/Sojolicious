#!/usr/bin/env perl
use Test::More skip_all => 'No MySQL db connection available.';
use strict;
use warnings;

use Data::Dumper;

use lib '../lib', '../../lib', '../../../lib';
#use_ok 'Sojolicious::Oro';

use Sojolicious::Oro;

my $oro = Sojolicious::Oro->new(
  driver => 'MySQL',
  database => 'sgf'
);

warn 'Oro!';
