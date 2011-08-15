package Mojolicious::Plugin::MagicSignatures;
use Mojo::Base 'Mojolicious::Plugin';

use Mojolicious::Plugin::MagicSignatures::Envelope;
use Mojolicious::Plugin::MagicSignatures::Key;

our $me_ns;
BEGIN {
    $me_ns = 'http://salmon-protocol.org/ns/magic-key';
};

# Register plugin
sub register {
    my ($plugin, $mojo) = @_;

    for ($mojo->types) {
	$_->type('mkey'    => 'application/magic-key');
	$_->type('me+xml'  => 'application/magic-envelope+xml');
	$_->type('me+json' => 'application/magic-envelope+json');
    };

    $mojo->helper(
	'magicenvelope' => sub {
	    return $plugin->magicenvelope(@_);
	});

    $mojo->helper(
	'magickey' => sub {
	    return $plugin->magickey(@_);
	});

    $mojo->helper(
	'verify_magicenvelope' => sub {
	    return $plugin->verify_magicenvelope(@_);
	});
};

# MagicEnvelope
sub magicenvelope {
    my $plugin = shift;
    shift; # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
    
    # New MagicEnvelope instance object.
    my $me = Mojolicious::Plugin::MagicSignatures::Envelope->new( @_ );

    # MagicEnvelope can not be build
    if (!$me || !$me->data) {
	warn 'Unable to create magic envelope';
	return;
    };

    # Return MagicEnvelope
    return $me;
};

# MagicKey
sub magickey {
    my $plugin = shift;
    shift;  # Controller is not interesting
    # Possibly interesting for $c->push_to('http://...');
   
    # New MagicKey instance
    return Mojolicious::Plugin::MagicSignatures::Key->new(@_);
};

# Verify MagicEnvelope
sub verify_magicenvelope {
    my $plugin = shift;
    my $c = shift;
    my $me = shift;
    my %param = %{ shift(@_) };

    my $public_mkey = $param{'key'} || undef;

    # Discover public key
    unless ($public_mkey) {
	my $acct;

	# Use direct key access
	if (exists $param{key_url}) {
	    # application/metadata+json. If so, look for the "magic_public_keys
	}

	# Use webfinger information
	elsif (exists $param{acct}) {
	    $acct = $param{acct};
	}

	# Discover based on Webfinger acct
	if (!$public_mkey && $acct) {
	    my $wf_xrd = $c->webfinger($acct);
	    
	    # Unable to find public MagicKey
	    return 0 unless $wf_xrd;
	    
	    # Discovery based on spec-01
	    # Key id is not specified
	    unless (defined $param{key_id}) {
		my $public_mkey_prop = $wf_xrd->get_property( $me_ns );
		$public_mkey = $public_mkey_prop->text(0) if $public_mkey_prop;

	    }

	    # Key id is specified
	    else {
		my $key_id = $param{key_id};
		foreach (@{$wf_xrd->find('Property[rel="' . $me_ns . '"]')}) {
		    
		    # Get key_ids from property
		    my ($key_id_key) = grep(/key_id$/, keys %{ $_->attrs });
		    
		    # Return public mkey if key_id is correct
		    if ($key_id eq $_->attrs($key_id_key)) {
			$public_mkey = $_->text(0);
			last;
		    };
		};
	    };

	    # Discovery based on spec-00
	    unless ($public_mkey) {

		my $public_key_link = $wf_xrd->get_link('magic-public-key');

		if ( $public_key_link ) {
		    $public_mkey = $public_key_link->attrs('href');
		    $public_mkey =~ s/^data:application\/magic-public-key,\s*//;
		};
	    };
	};	
    };

    # Unable to find public MagicKey
    return 0 unless $public_mkey;
	
    $public_mkey =
	Mojolicious::Plugin::MagicSignatures::Key->new($public_mkey);
    
    my $signature = $param{sig} || undef;
    $signature = $me->sign($param{key_id} || undef) unless $signature;

    return 0 unless $signature;

    # Return verification value
    return $public_mkey->verify($me->data, $signature);
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

=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicSignatures> is a plugin for L<Mojolicious>
to fold and unfold MagicEnvelopes as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 HELPERS

=head2 C<magicenvelope>

L<Mojolicious::Plugin::MagicSignatures> establishes a helper
called C<magicenvelope>. This helper accepts magicenvelope data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicSignatures::Envelope> C<new>
for acceptable parameters).

On success the helper returns a C<Mojolicious::Plugin::MagicSignatures::Envelope>
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
called C<magickey>. This helper accepts MagicKey data
in various formats and can be used from all L<Mojolicious::Controller>
classes (see L<Mojolicious::Plugin::MagicSignatures::Key> C<new> for
acceptable parameters).

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
the second parameter is an optional Hashref, containing
several possible parameters.
If no second parameter is given, it is assumed that the
MagicEnvelope contains an Atom document with a given
entry/author/uri element. This uri will be used for
discovery by applying a webfinger data retrieval.

The Hashref can contain the following parameters

=over2

=item C<key_id>:  ID of the key
=item C<key>:     The MagicKey as a string or a MagicKey object
=item C<acct>:    The Webfinger Account name for discovery
=item C<key_url>: The url of the MagicKey or a set of MagicKeys
                  as defined in section 8.2 of the spec
=item C<sig>:     A specified signature value

=back

B<This method is experimental and can change without warning!>

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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
