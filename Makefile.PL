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
        'Mojolicious' => 3.91,
        'DBIx::Oro'   => 0.28,
	'XML::Loy'    => 0.13,
        'Mojolicious::Plugin::Util::Endpoint' => 0.12,
        'Mojolicious::Plugin::Util::Callback' => 0.02,
        'Mojolicious::Plugin::PubSubHubbub'   => 0.07,
	'Mojolicious::Plugin::XRD'            => 0.02,
	'Mojolicious::Plugin::HostMeta'       => 0.01,
        'Mojolicious::Plugin::Oro'            => 0.01,
        'Mojolicious::Plugin::CHI'            => 0.06,
        'Mojolicious::Plugin::XML::Loy'       => 0.03,
        'Crypt::MagicSignatures::Key'         => 0.08,
	'Crypt::MagicSignatures::Envelope'    => 0.05,
	'Test::More'  => 0
    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t'}
);

