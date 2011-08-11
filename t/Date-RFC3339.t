#!/usr/bin/env perl

use strict;
use warnings;
$|++;
use lib '../lib';

use Test::More tests => 12;

# "Can't we have one meeting that doesn't end with digging up a corpse?"
use_ok 'Mojolicious::Plugin::Date::RFC3339';

my $date = Mojolicious::Plugin::Date::RFC3339->new(784111777);
is $date->to_string, '1994-11-06T08:49:37Z', 'right date';

$date = Mojolicious::Plugin::Date::RFC3339->new('2011-07-30T16:30:00Z');
is($date, '2011-07-30T16:30:00Z', 'Date1');
is($date->epoch, 1312043400, 'Date2');

$date = Mojolicious::Plugin::Date::RFC3339->new(1312043400);
is($date, '2011-07-30T16:30:00Z', 'Date3');
is($date->epoch, 1312043400, 'Date4');

# Offset
$date = Mojolicious::Plugin::Date::RFC3339->new('1993-01-01t18:50:00-04:00');
is $date->to_string, '1993-01-01T22:50:00Z', 'right date';

# Offset
$date = Mojolicious::Plugin::Date::RFC3339->new('1993-01-01t22:50:00-04:00');
is $date->to_string, '1993-01-02T02:50:00Z', 'right date';
is $date->epoch, '725943000', 'right epoch';

# Relaxed
$date = Mojolicious::Plugin::Date::RFC3339->new('1993-1-1t18:50:0-4');
is $date->to_string, '1993-01-01T22:50:00Z', 'right date';

# Negative epoch value
$date = Mojolicious::Plugin::Date::RFC3339->new;
ok $date->parse('1900-01-01T00:00:00Z'), 'right format';
is $date->epoch, undef, 'no epoch value';
