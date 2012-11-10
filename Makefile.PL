#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    VERSION_FROM => 'Readme.pod',
    NAME         => 'Sojolicious',
    AUTHOR       => 'Nils Diewald',
    PREREQ_PM => {
        'Mojolicious' => 3.43,
        'DBIx::Oro'   => 0.21,
        'Mojolicious::Plugin::Util::Endpoint'   => 0.03,
        'Mojolicious::Plugin::PubSubHubbub'   => 0.01,
        'Mojolicious::Plugin::Oro'   => 0.01,
        'Mojolicious::Plugin::CHI'   => 0.01,
	'Test::More'  => 0
    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t'}
);

