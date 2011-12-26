#!/usr/bin/env perl
use Test::Mojo;
use Test::More tests => 18;
use Mojolicious::Lite;
use strict;
use warnings;

$|++;

use lib '../../lib';

my $t = Test::Mojo->new;

my $app = $t->app;

$app->plugin('Util::ArbitraryBase' => {
  base26 => '2345679bdfhmnprtFGHJLMNPRT',
  base32 => ['A'..'Z',2..7],
  base5  => 'aeiou',
  foobar => 'qwerty'
});

my $c = Mojolicious::Controller->new;
$c->app($app);

my $num = 185872;
my $val;

is($val = $c->base26_encode($num), 'hrRR', 'base26');
is($c->base26_decode($val), $num, 'base26');

$num = 11111111111;
is($val = $c->base26_encode($num), '3fT6m6Pf', 'base26');
is($c->base26_decode($val), $num, 'base26');

$num = 357357357;
is($val = $c->base26_encode($num), '364255J', 'base26');
is($c->base26_decode($val), $num, 'base26');

$num = 123456789000000;
is($val = $c->base26_encode($num), 'NJ6Tn4mRGr', 'base32');
is($c->base26_decode($val), $num, 'base26');

$num = 11111111111;
is($val = $c->base32_encode($num), 'KLEMGOH', 'base32');
is($c->base32_decode($val), $num, 'base32');

$num = 357357357;
is($val = $c->base32_encode($num), 'KUZVZN', 'base32');
is($c->base32_decode($val), $num, 'base32');

$num = 123456789000000;
is($val = $c->base32_encode($num), 'DQJCDA3L2A', 'base32');
is($c->base32_decode($val), $num, 'base32');

$num = 465578;
is($val = $c->base5_encode($num), 'eauouuoao', 'base5');
is($c->base5_decode($val), $num, 'base5');
is($val = $c->foobar_encode($num), 'wryywete', 'base5');
is($c->foobar_decode($val), $num, 'base5');
