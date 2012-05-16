package Mojolicious::Plugin::MagicSignatures;
use Mojo::Base 'Mojolicious::Plugin';

use Mojolicious::Plugin::MagicSignatures::Envelope;
use Mojolicious::Plugin::MagicSignatures::Key;

use constant ME_NS => 'http://salmon-protocol.org/ns/magic-key';


# Register plugin
sub register {
  my ($plugin, $mojo) = @_;

  # Set mime-types
  for ($mojo->types) {
    $_->type('mkey'    => 'application/magic-key');
    $_->type('me+xml'  => 'application/magic-envelope+xml');
    $_->type('me+json' => 'application/magic-envelope+json');
  };

  # Load Webfinger if not already loaded.
  unless (exists $mojo->renderer->helpers->{'webfinger'}) {
    $mojo->plugin('Webfinger');
  };

  # Add 'magicenvelope' helper
  $mojo->helper(
    'magicenvelope' => sub {
      # New MagicEnvelope instance object
      my $me = Mojolicious::Plugin::MagicSignatures::Envelope
	->new( @_[1..$#_] );

      # MagicEnvelope can not be build
      return if (!$me || !$me->data);

      # Return MagicEnvelope
      return $me;
    });

  # Add 'magickey' helper
  $mojo->helper(
    'magickey' => sub {
      # New MagicKey instance object
      return Mojolicious::Plugin::MagicSignatures::Key
	->new( @_[1..$#_] );
    });

  # Add 'verify_magicenvelope' helper
  $mojo->helper(
    'verify_magicenvelope' => sub {
      return $plugin->verify_magicenvelope( @_ );
    });

  # Add 'get_magickeys' helper
  $mojo->helper(
    'get_magickeys' => sub {
      return $plugin->get_magickeys( @_ );
    });

  # Add magickey to webfinger document
  $mojo->hook(
    'before_serving_webfinger' => sub {
      my ($c, $acct, $xrd) = @_;

      # Get keys
      my $mkeys = $c->get_magickeys(
	'acct'      => $acct,
	'discovery' => 0
      );

      return unless defined $mkeys->[0];

      # Structure is = [[mkey,id?]+]

      # Based on spec-00
      # Only allowed for one single key (for the moment)
      unless (defined $mkeys->[1]) {
	my $mkey = $mkeys->[0]->[0];
	$xrd->add_link(
	  'magic-public-key' => {
	    href => 'data:application/magic-public-key,' . $mkey->to_string
	  }
	)->comment('MagicKey based on MagicSignatures-00');
      };

      # Based on spec-01
      my $first = 0;
      foreach my $mkey (@$mkeys) {
	my %att_hash = ('-type' => 'base64');

	if ($mkey->[1]) {
	  $xrd->add_ns('mk' => ME_NS) unless $first++;
	  $att_hash{'mk:key_id'} = $mkey->[1] ;
	};

	$xrd->add_property(
	  ME_NS,
	  \%att_hash,
	  $mkey->[0]->to_string
	)->comment('MagicKey based on MagicSignatures-01');
      };
      return;
    });
};


# Get MagicKeys
sub get_magickeys {
  my $plugin = shift;
  my $c      = shift;
  my %param  = @_;

  # Enable discovery if not explicitely forbidden
  $param{discovery} = 1 unless exists $param{discovery};

  my @magickeys;

  # Run hook for caching or database retrieval
  $c->app->plugins->run_hook(
    'before_fetching_magickeys' => (
      $plugin, $c, \%param, \@magickeys
    ));

  # Discover public key
  if (!$magickeys[0] && $param{discovery}) {
    my $acct;

    # Use direct key access
    if (exists $param{key_url}) {
      # todo
      # application/metadata+json. If so, look for the "magic_public_keys
    }

    # Use webfinger information
    elsif (exists $param{acct}) {
      $acct = $param{acct};
    };

    # Discover based on Webfinger acct
    if (!$magickeys[0] && $acct) {
      my $wf_xrd = $c->webfinger($acct);

      # Unable to find public MagicKey
      return 0 unless $wf_xrd;

      # Discovery based on spec-01
      # Key id is not specified
      unless (exists $param{key_id}) {
	foreach (@{ $wf_xrd->find('Property[type="'.ME_NS.'"]')}) {

	  # Create key from property
	  my @key = ($plugin->magickey($c, $_->text(0)));
	  next unless $key[0];

	  # Get key_id from property
	  my ($key_id_key) = grep(/key_id$/, keys %{ $_->attrs });
	  push(@key, $_->attrs($key_id_key)) if $key_id_key;

	  # Add key to array
	  push(@magickeys, \@key)
	};
      }

      # Key id is specified, maybe undef
      else {
	my $key_id = $param{key_id};
	foreach (@{$wf_xrd->find('Property[type="'.ME_NS.'"]')}) {

	  # Get key_ids from property
	  my ($key_id_key) = grep(/key_id$/, keys %{ $_->attrs });

	  # Return public mkey if key_id is correct
	  if (
	    (!defined $key_id && !$key_id_key) ||
	      ($key_id eq $_->attrs($key_id_key))
	    ) {

	    # Create key from property
	    my @key = ($plugin->magickey($c, $_->text(0)));
	    next unless $key[0];

	    # Use key_id
	    push(@key, $key_id) if defined $key_id;

	    # Add key to array
	    push(@magickeys, \@key);
	  };
	};
      };

      # Discovery based on spec-00
      unless ($magickeys[0]) {

	# Currently no array og magic keys is supported

	my $mkey_link = $wf_xrd->get_link('magic-public-key');

	if ( $mkey_link ) {
	  my $key = $mkey_link->attrs('href');
	  $key =~ s/^data:application\/magic-public-key,\s*//;

	  my $mkey = $c->magickey($key);

	  return unless $mkey;

	  push(@magickeys,[$mkey]);
	};
      };
    };

    # Run hook for caching
    $c->app->plugins->run_hook(
      'after_fetching_magickeys',
      $plugin,
      $c,
      \%param,
      \@magickeys
    );
  };

  return \@magickeys;
};


# Verify MagicEnvelope
sub verify_magicenvelope {
  my $plugin = shift;
  my $c      = shift;
  my $me     = shift;
  my %param  = %{ shift(@_) };

  my $mkey = $param{'key'} || undef;

  # If key_id does not exist, set to undef (default key)
  $param{key_id} = undef unless exists $param{key_id};

  # Start key discovery
  unless ($mkey) {
    my $mkeys = $plugin->get_magickeys($c, %param);
    $mkey = shift(@$mkeys);
  };

  # Unable to find public MagicKey
  return 0 unless $mkey;

  # Create MagicKey from whatever representation is given
  $mkey = $c->magickey($mkey);

  # Get signature to verify
  my $signature = $param{sig} || undef;
  $signature = $me->signature($param{key_id} || undef) unless $signature;

  # No signature can be found for verification
  return 0 unless $signature;

  # Return verification value
  # TODO: me->verif instead!
  return $mkey->verify($me->sig_base, $signature);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::MagicSignatures - MagicSignatures Plugin for Mojolicious

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('MagicSignatures');

  # Mojolicious::Lite
  plugin 'MagicSignatures';

  # In Controller:
  # Fold data in MagicEnvelope
  my $me = $c->magicenvelope({
                data => 'Some arbitrary string.'
                data_type => 'text/plain'
              });

  # Create MagicKey
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

  $me->sign({'key'  => 'RSA.vsd...'});
  # or
  $me->sign($mkey);

  $c->render(format => 'me+xml',
             data   => $me->to_xml);

  # Unfold MagicEnvelope
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

  # Verify MagicEnvelope
  if ($self->verify_magicenvelope($me) > 0) {
    print $me->data, " is verified!\n";
  };

  # Fetch MagicKeys
  my $magickeys = $c->get_magickeys(acct => 'akron@sojolicio.us');

=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicSignatures> is a plugin for L<Mojolicious>
to fold and unfold MagicEnvelopes as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.


=head1 METHODS

=head2 C<register>

  # Mojolicious
  $app->plugin('MagicSignatures');

  # Mojolicious::Lite
  plugin 'MagicSignatures';

Called when registering the plugin.


=head1 HELPERS

=head2 C<magicenvelope>

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

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<magicenvelope>. This helper accepts magicenvelope data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicSignatures::Envelope> C<new>
for acceptable parameters).

On success the helper returns a C<Mojolicious::Plugin::MagicSignatures::Envelope>
object.

=head2 C<magickey>

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

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<magickey>. This helper accepts MagicKey data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicSignatures::Key> C<new> for
acceptable parameters).


=head2 C<get_magickeys>

  my $mkeys = $c->get_magickeys('acct' => 'acct:akron@sojolicio.us');

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<get_magickeys>.
It accepts a hash containing the following parameters

=over 2

=item C<acct>:     The Webfinger Account name for discovery
=item C<key_url>:  The url of the MagicKey or a set of MagicKeys
                   as defined in section 8.2 of the spec
=item C<key_id>:   ID of the key. If this parameter is not given,
                   all keys are returned. If only one or
                   the default key should be returned, use
                   C<key_id => undef>.
=item C<discovery> Enable or disable discovery at all.
                   Defaults to 1.

=back

Additional parameters are allowed and may be used for
database requests, see L<HOOKS>.

This helper returns MagicKeys of a given user as an array
reference of the following structure:

  [ [ MagicKey, key_id? ]* ]

The MagicKeys may or may not contain a private part.


=head2 C<verify_magicenvelope>

  if ($c->verify_magicenvelope($me) > 0) {
    print "Origin is verified.\n";
  }

  $c->verify_magicenvelope(
        $me => {
          key    => 'RSA.mVgY ...'
          key_id => 'key-1',
          acct   => 'akron@sojolicio.us',
	  sig    => 'S1VqYVlIWFpu ...'
        });

Verifies the signature of a MagicEnvelope.
The first parameter has to be a MagicEnvelope object,
the second parameter is an optional Hash reference,
containing the possible parameters for L<get_magickeys>
and the following in addition:

=over 2

=item C<key>:     The MagicKey as a string or a MagicKey object
=item C<sig>:     A specified signature value

=back

If no C<key_id> is given, C<key_id => 'undef'> is assumed.

If no second parameter is given, it is assumed that the
MagicEnvelope contains an Atom document with a given
entry/author/uri element. This uri will be used for
discovery.

B<This method is experimental and can change without warning!>

=head1 HOOKS

=head2 C<before_fetching_magickeys>

This hook is run before MagicKeys are requested by the L<get_magickeys>
helper.
The hook passes the current plugin object, the controller object,
the requested parameters and an array reference, meant to contain
the MagicKeys in the following structure:

  [ [ MagicKey, key_id? ]* ]

This hook is expected to be used for caching as well as for retrieving
private MagicKeys from a database.

If the array reference is filled, no further discovery is applied.
That means, no values should be returned, if they only partially
match the given parameters.

=head2 C<after_fetching_magickeys>

This hook is run after MagicKeys are requested by the L<get_magickeys>
helper and discovery was applied.
The hook passes the current plugin object, the controller object,
the requested parameters and an array reference, containing the fetched
MagicKeys in the following structure:

  [ [ MagicKey, key_id? ]* ]

This hook is expected to be used for caching.

=head1 MIME-TYPES

L<Mojolicious::Plugin::MagicSignatures> establishes the following
mime-types:

  'mkey':    'application/magic-key'
  'me+xml':  'application/magic-envelope+xml'
  'me+json': 'application/magic-envelope+json'

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::MagicSignatures::Envelope>,
L<Mojolicious::Plugin::MagicSignatures::Key>,
L<Mojolicious::Plugin::Webfinger>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
