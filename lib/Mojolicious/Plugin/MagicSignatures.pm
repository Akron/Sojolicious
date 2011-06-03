package Mojolicious::Plugin::MagicSignatures;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::MagicEnvelope;
use Mojolicious::Plugin::MagicKey;

# Register plugin
sub register {
    my ($plugin, $mojo) = @_;

    my $types = $mojo->types;
    $types->type('me-key'  => 'application/magic-key');
    $types->type('me-xml'  => 'application/magic-envelope+xml');
    $types->type('me-json' => 'application/magic-envelope+json');

    $mojo->helper(
	'magicenvelope' => sub {
	    return $plugin->magicenvelope(@_);
	});

    $mojo->helper(
	'magickey' => sub {
	    return $plugin->magickey(@_);
	});
};

# MagicEnvelope
sub magicenvelope {
    my $plugin = shift;
    shift; # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
   
    # New me::instance object.
    my $me = Mojolicious::Plugin::MagicEnvelope->new( @_ );

    # MagicEnvelope can not be build
    if (!$me || !$me->data) {
	warn 'Unable to create magic envelope';
	return;
    };

    # Return me
    return $me;
};

# MagicKey
sub magickey {
    my $plugin = shift;
    shift;  # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
   
    return Mojolicious::Plugin::MagicKey->new(@_);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::MagicSignatures - MagicSignatures Plugin for Mojolicious

=head1 SYNOPSIS

  # In Mojolicious startup
  $app->plugin('magic_signatures');

  # In Controller:
  # Fold data in magic envelope
  my $me = $c->magicenvelope({
                data => 'Some arbitrary string.'
                data_type => 'text/plain'
              });

  $me->sign({'key'  => 'RSA.vsd...'});

  $c->render(format => 'me-xml',
             data   => $me->to_xml);

  # Unfold magic envelope
  $me = $c->magicenvelope(<<'MEXML');
  <?xml version="1.0" encoding="UTF-8"?>
  <me:env xmlns:me="http://salmon-protocol.org/ns/magic-env">
    <me:data type="text/plain">
      U29tZSBhcmJpdHJhcnkgc3RyaW5nLg==
    </me:data>
    <me:encoding>base64url</me:encoding>
    <me:alg>RSA-SHA256</me:alg>
    <me:sig key_id="my-01">
      S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVluZkI5Ulh4dmRFSnFhQW5XUmpB
      UEJqZUM0b0lReER4d0IwWGVQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ==
    </me:sig>
  </me:env>
  MEXML

  if ($me->verified > 0) {
    print $me->data, " is verified!\n";
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicSignature> is a plugin for L<Mojolicious>
to fold and unfold Magic Envelopes as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 HELPERS

=head2 C<magicenvelope>

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<magicenvelope>. This helper accepts magicenvelope data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicEnvelope> C<new> for acceptable
parameters).

On success the helper returns a C<Mojolicious::Plugin::MagicEnvelope>
object.

  my $me = $c->magicenvelope(<<'MEXML');
  <?xml version="1.0" encoding="UTF-8"?>
  <me:env xmlns:me="http://salmon-protocol.org/ns/magic-env">
    <me:data type="text/plain">
      U29tZSBhcmJpdHJhcnkgc3RyaW5nLg==
    </me:data>
    <me:encoding>base64url</me:encoding>
    <me:alg>RSA-SHA256</me:alg>
    <me:sig key_id="my-01">
      S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVluZkI5Ulh4dmRFSnFhQW5XUmpB
      UEJqZUM0b0lReER4d0IwWGVQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ==
    </me:sig>
  </me:env>
  MEXML

=head2 C<magickey>

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<magickey>. This helper accepts magickey data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicKey> C<new> for acceptable
parameters).

  my $mkey = $c->magickey(<<'MKEY');
  RSA.
  mVgY8RN6URBTstndvmUUPb4UZTdwvw
  mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
  FilGj9K0eeUPe2hf4Pj-5CmHww==.
  AQAB.
  Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6
  yihYetQ8jy-jZXdsZXd8V5ub3kuBHH
  k4M39i3TduIkcrjcsiWQb77D8Q==
  MKEY

=head1 MIME-TYPES

L<Mojolicious::Plugin::MagicSignatures> establishes the following
mime-types:

  'me-key':  'application/magic-key'
  'me-xml':  'application/magic-envelope+xml'
  'me-json': 'application/magic-envelope+json'

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::MagicEnvelope>,
L<Mojolicious::Plugin::MagicKey>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
