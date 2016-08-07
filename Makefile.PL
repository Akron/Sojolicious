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
        'DBIx::Oro'   => 0.31,
	'XML::Loy'    => 0.44,
        'Mojolicious::Plugin::Util::Endpoint' => 0.19,
        'Mojolicious::Plugin::Util::Callback' => 0.04,
        'Mojolicious::Plugin::PubSubHubbub'   => 0.16,
	'Mojolicious::Plugin::XRD'            => 0.17,
	'Mojolicious::Plugin::HostMeta'       => 0.21,
        'Mojolicious::Plugin::Oro'            => 0.07,
        'Mojolicious::Plugin::CHI'            => 0.13,
        'Mojolicious::Plugin::XML::Loy'       => 0.14,
        'Mojolicious::Plugin::TagHelpers::Pagination' => 0.06,
        'Crypt::MagicSignatures::Key'         => 0.14,
	'Crypt::MagicSignatures::Envelope'    => 0.10,
	'Test::More'  => 0
    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t'}
);

