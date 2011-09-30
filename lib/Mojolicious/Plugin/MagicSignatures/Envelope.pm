package Mojolicious::Plugin::MagicSignatures::Envelope;
use Mojo::Base '-base';

use Mojolicious::Plugin::Util::Base64url;
use Mojolicious::Plugin::MagicSignatures::Key;

use Mojo::Command;
use Mojo::DOM;
use Mojo::Template;
use Mojo::JSON;

has 'data';
has alg       => 'RSA-SHA256';
has encoding  => 'base64url';
has data_type => 'text/plain';

# MagicEnvelope namespace
use constant
  ME_NS => 'http://salmon-protocol.org/ns/magic-env';


# Constructor
sub new {
  my $class = shift;

  # Bless object as parent class
  my $self = $class->SUPER::new;
  $self->{sigs}     = [];
  $self->{sig_base} = '';

  # Message is me-xml
  if ($_[0] =~ /^[\s\t\n]*\</) {

    my $dom = Mojo::DOM->new(xml => 1);
    $dom->parse( shift );

    # Extract envelope from env or provenance
    my $env = $dom->at('env');
    $env = $dom->at('provenance') unless $env;
    return if (!$env || $env->namespace ne ME_NS);

    # Retrieve and edit data
    my $data = $env->at('data');

    # Envelope empty
    return unless $data;

    $self->data_type( $data->attrs->{type} ) if $data->attrs->{type};
    $self->data( b64url_decode ( $data->text ) );

    # Check algorithm
    if ($env->at('alg') &&
	  ($env->at('alg')->text ne 'RSA-SHA256')) {
      warn 'Algorithm currently not supported.' and return;
    };

    # Check encoding
    if ($env->at('encoding') &&
	  ($env->at('encoding')->text ne 'base64url')) {
      warn 'Encoding currently not supported.' and return;
    };

    # Find signatures
    $env->find('sig')->each(
      sub {
	return unless $_->text;

	my %sig = ( value => $_->text );

	if (exists $_->attrs->{key_id}) {
	  $sig{key_id} = $_->attrs->{key_id};
	};

	# Add sig to array
	push( @{ $self->{sigs} }, \%sig );

	# Envelope is signed
	$self->{signed} = 1;
      });
  }

  # Message is me-json
  elsif (
    (ref $_[0] && (ref $_[0] eq 'HASH')) ||
      $_[0] =~ /^[\s\t\n]*\{/ ) {
    my $env;

    # Message is me-json (as a datastructure)
    if (ref $_[0]) {
      $env = shift;
    }

    # Message is me-json (as a string)
    else {
      # Parse json object
      $env = Mojo::JSON->new->decode( shift );
      return unless $env;
    };

    # Clone datastructure
    foreach (qw/data data_type encoding alg sigs/) {
      $self->{$_} = delete $env->{$_} if exists $env->{$_};
    };

    # Envelope is signed
    $self->{signed} = 1 if $self->{sigs}->[0];

    # Unknown parameters
    warn 'Unknown parameters: '.join(',', %$env)
      if keys %$env;
  }

  # Message is me as a compact string
  elsif (index($_[0], '.YmFzZTY0dXJs.')) {

    # Parse me compact string
    my $value = [];
    foreach (@$value = split(/\./, shift ) ) {
      $_ = b64url_decode( $_ ) if $_;
    };

    # Store sig to data structure
    for ($self->{sigs}->[0]) {
      next unless $value->[1];
      $_->{key_id}    = $value->[0] if defined $value->[0];
      $_->{value}     = $value->[1];
      $self->{signed} = 1;
    };

    # Store values to data structure
    for ($value) {

      # ME is empty
      return unless $_->[2];

      $self->data( $_->[2] );
      if ($_->[3]) { $self->data_type( $_->[3] ) };
      if ($_->[4]) { $self->encoding( $_->[4] ) };
      if ($_->[5]) { $self->alg( $_->[5] ) };
    };
  }

  # Message has unknown format
  else {
    warn 'Envelope has unknown format.' and return;
  };

  return $self;
};


# Sign magic envelope instance
sub sign {
  my ( $self,
       $key,
       $key_id ) = @_;

  # Todo: Regarding key id:
  # "If the signer does not maintain individual key_ids,
  #  it SHOULD output the base64url encoded representation
  #  of the SHA-256 hash of public key's application/magic-key
  #  representation."

  # A valid key is given
  if ($key) {

    # Create MagicKey from parameter
    my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new(
      ( ref $key && $key eq 'HASH' ? %{ $key } : $key )
    );

    # No valid private key
    return undef unless ($mkey && $mkey->d);

    # Compute signature for base string
    my $msig = $mkey->sign( $self->sig_base );

    # No valid signature
    return undef unless $msig;

    # Sign envelope
    my %msig = ( value => $msig );
    $msig{key_id} = $key_id if defined $key_id;

    # Push signature
    push( @{ $self->{sigs} }, \%msig );

    # Declare envelope as signed
    $self->{signed} = 1;

    # Return envelope for piping
    return $self;
  };

  return;
};


# Verify Signature
sub verify {
  my $self      = shift;

  # public keys of the author
  my @key_bunch = @{ shift(@_) };

  # Regarding key id:
  # "If the signer does not maintain individual key_ids,
  #  it SHOULD output the base64url encoded representation
  #  of the SHA-256 hash of public key's application/magic-key
  #  representation."

  # No sig base - MagicEnvelope is invalid
  return unless $self->sig_base;

  my $verified = 0;
  # Only one key in bunch
  if (@key_bunch == 1) {

    # Get without key id
    my $sig = $self->signature;

    if ($sig) {
      # Found key/sig pair
      my $mkey =
	Mojolicious::Plugin::MagicSignatures::Key->new($key_bunch[0]->[0]);

      $verified = $mkey->verify($self->sig_base => $sig->{value}) if $mkey;
    };
  }

  # Multiple keys in bunch
  else {
    foreach my $key (@key_bunch) {

      # key id given
      my $sig = $self->signature($key->[1] || undef);

      if ($sig) {
	# Found key/sig pair
	my $mkey =
	  Mojolicious::Plugin::MagicSignatures::Key->new($key->[0]);

	$verified = $mkey->verify($self->sig_base => $sig->{value}) if $mkey;

	last if $verified;
      };
    };
  };

  return $verified;
};


# Retrieve MagicEnvelope signatures
sub signature {
  my ( $self,
       $key_id ) = @_;

  # MagicEnvelope has no signature
  return unless $self->signed;

  my @sigs = @{ $self->{sigs} };

  # No key_id given
  unless ($key_id) {

    # Search sigs for necessary default key
    foreach (@sigs) {
      unless (exists $_->{key_id}) {
	return $_;
      };
    };

    # Return first sig
    return $sigs[0];
  }

  # Key is given
  else {
    my $default;

    # Search sigs for necessary specific key
    foreach (@sigs) {

      # sig specifies key
      if (defined $_->{key_id}) {

	# Found wanted key
	if ($_->{key_id} eq $key_id) {
	  return $_;
	};
      }

      # sig needs default key
      else {
	$default = $_;
      };
    };

    # Return sig for default key
    return $default;
  };

  # No matching sig found
  return;
};


# Is the MagicEnvelope signed?
sub signed {

  # There is no specific key_id requested
  return $_[0]->{signed} unless defined $_[1];

  # Check for specific key_id
  foreach my $sig (@{ $_[0]->{sigs} }) {
    return 1 if $sig->{key_id} eq $_[1];
  };

  # Envelope is not signed
  return 0;
};


# Generate and return signature base
sub sig_base {
  my $self = shift;

  # Already computed
  return $self->{sig_base} if $self->{sig_base};

  $self->{sig_base} = join('.',
			   b64url_encode( $self->data, 0 ),
			   b64url_encode( $self->data_type ),
			   b64url_encode( $self->encoding ),
			   b64url_encode( $self->alg )
			 );

  unless ($self->{sig_base}) {
    warn 'Unable to construct sig_base.';
  };

  return $self->{sig_base};
};


# Return the data as a Mojo::DOM if it is xml
sub dom {
  my $self = shift;

  # Already computed
  return $self->{dom} if $self->{dom};

  # Create new DOM instantiation
  my $dom = Mojo::DOM->new;
  if (index($self->{data_type}, 'xml') >= 0) {
    $dom->parse( $self->{data} );
  };

  # Return DOM instantiation (Maybe empty)
  return ($self->{dom} = $dom);
};


# Return em-xml string
sub to_xml {
  my $self = shift;

  # UGLY!
  # Todo - better: renderer-> get_data_template?
  my $template = Mojo::Command->new->get_data(
    'magicenvelope.xml.ep',
    __PACKAGE__);

# Todo:
#    $self->log->error(qq{Template not found: $me_templ!})
#	and return unless $template;

  return Mojo::Template->new->render($template, $self);
};


# Return em-compact string
sub to_compact {
  my $self = shift;

  # The me has to be signed
  return unless $self->signed;

  # Use default signature for serialization
  my $sig = $self->signature;

  return join( '.',
	       b64url_encode( $sig->{key_id} ) || '',
	       b64url_encode( $sig->{value} ),
	       $self->sig_base );
};


# Return em-json string
sub to_json {
  my $self = shift;

  # Empty envelope
  return '{}' unless $self->data;

  # Create new datastructure
  my %new_em = (
    alg       => $self->alg,
    encoding  => $self->encoding,
    data_type => $self->data_type,
    data      => b64url_encode( $self->data ),
    sigs      => []
  );

  # loop through signatures
  foreach my $sig ( @{ $self->{sigs} } ) {
    my %msig = ( value => b64url_encode( $sig->{value} ) );
    $msig{key_id} = $sig->{key_id} if defined $sig->{key_id};
    push( @{ $new_em{sigs} }, \%msig );
  };

  # Return json-string
  return Mojo::JSON->new->encode( \%new_em );
};


1;

__DATA__

@@ magicenvelope.xml.ep
% use Mojolicious::Plugin::Util::Base64url;
% my $me = shift;
% my $start_tag = 'env';
% if ($me->{embed}) {
% $start_tag = 'provenance';
<% } else { =%>
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
% }
<me:<%= $start_tag %> xmlns:me="http://salmon-protocol.org/ns/magic-env">
  <me:data<% if (exists $me->{'data_type'}) { =%>
<%= ' ' %>type="<%== $me->{'data_type'} %>"<% } =%>
>
    <%= b64url_encode( $me->data , 0) %>
  </me:data>
  <me:encoding><%= $me->encoding %></me:encoding>
  <me:alg><%= $me->alg %></me:alg>
% foreach my $sig (@{$me->{'sigs'}}) {
  <me:sig<% if ($sig->{'key_id'}) { =%>
<%= ' ' %>key_id="<%== $sig->{'key_id'} %>"<% } =%>
>
    <%= b64url_encode($sig->{'value'}) %>
  </me:sig>
% }
</me:env>

__END__

=pod

=head1 NAME

Mojolicious::Plugin::MagicSignatures::Envelope - MagicEnvelope Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Plugin::MagicSignatures::Envelope;

  my $me = Mojolicious::Plugin::MagicSignatures::Envelope->new(
             {
               data => 'Some arbitrary string.',
               data_type => 'text/plain'
             }
           );

  $me = Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'MEXML');
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

  $me->sign('key-01' => 'RSA.vsd...');

=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicSignatures::Envelope> is a plugin for
L<Mojolicious> to work with MagicEnvelopes as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 ATTRIBUTES

=head2 C<alg>

  $me->alg;

The algorithm used for the folding of the MagicEnvelope.
Defaults to 'RSA-SHA256'.

=head2 C<data>

  $me->data;

The decoded data folded in the MagicEnvelope.

=head2 C<data_type>

  $me->data_type;

The mime type of the data folded in the MagicEnvelope.
Defaults to 'text/plain'.

=head2 C<dom>

  my $dom = $me->dom;

The L<Mojo::DOM> object of the decoded data,
if the magic envelope contains XML.

B<This attribute is experimental and can change without warning!>

=head2 C<encoding>

  $me->encoding;

The encoding of the MagicEnvelope.
Defaults to 'base64url'.

=head2 C<sig_base>

  $me->sig_base;

The signature base of the MagicEnvelope.

=head2 <signature>

  my $sig = $me->signature('key-01');
  my $sig = $me->signature;

Retrieves a signature from the MagicEnvelope.
For retrieving a specific signature, pass a key id,
otherwise a default signature will be returned.

If a matching signature is found, the signature
is returned as a hashref, containing data for C<value>
and possibly C<key_id>.
If no matching signature is found, false is returned.

B<This attribute is experimental and can change without warning!>

=head2 C<signed>

  # With key id
  if ($me->signed('key-01')) {
    print "Magic Envelope is signed with key-01.\n";
  }

  # Without key id
  elsif ($me->signed) {
    print "Magic Envelope is signed.\n";
  };

Returns C<true> when the MagicEnvelope is signed at least once.
Accepts optionally a C<key_id> and returns true, if the
MagicEnvelope was signed with this specific key.

B<This attribute is experimental and can change without warning!>

=head1 METHODS

=head2 C<new>

The L<Mojolicious::Plugin::MagicSignatures::Envelope> constructor accepts
magicenvelope data in various formats.

It accepts MagicEnvelopes in the XML format or an
XML document including an MagicEnvelope C<provenance> element.

  Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'MEXML');
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

Additionally it accepts MagicEnvelopes in the JSON notation.

  Mojolicious::Plugin::MagicEnvelope->new(<<'MEJSON');
  {
    "data_type": "text\/plain",
    "data":"U29tZSBhcmJpdHJhcnkgc3RyaW5nLg==",
    "alg":"RSA-SHA256",
    "encoding":"base64url",
    "sigs": [
      { "key_id": "my-01",
        "value":"S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVluZkI5U
                 lh4dmRFSnFhQW5XUmpBUEJqZUM0b0lReER4d0IwWG
                 VQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ=="
      }
    ]
  }
  MEJSON

The constructor also accepts MagicEnvelopes as a datastructure
with the same parameters as described in the JSON notation.
This is the common way to fold new envelopes.

  Mojolicious::Plugin::MagicSignatures::Envelope->new({
        data      => 'Some arbitrary string.',
        data_type => 'plain_text',
	alg       => 'RSA-SHA256',
	encoding  => 'base64url',
        sigs => [
          {
            key_id => 'my-01',
            value  => 'S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVluZkI5U
                       lh4dmRFSnFhQW5XUmpBUEJqZUM0b0lReER4d0IwWG
                       VQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ=='
          }
        ]
      });

Finally the constructor accepts MagicEnvelopes in the compact
MagicEnvelope notation.

  Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'MECOMPACT');
    bXktMDE=.S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVlu
    ZkI5Ulh4dmRFSnFhQW5XUmpBUEJqZUM0b0lReER4d0IwW
    GVQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ==.U29tZ
    SBhcmJpdHJhcnkgc3RyaW5nLg.dGV4dC9wbGFpbg.YmFz
    ZTY0dXJs.UlNBLVNIQTI1Ng
  MECOMPACT

=head2 C<sign>

  $me->sign( 'RSA.hgfrhvb ...', 'key-01' )
     ->sign( 'RSA.hgfrhvb ...' );

  my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new( 'RSA.hgfrhvb ...' )
  $me->sign( $mkey );

The sign method adds a signature to the MagicEnvelope.

For adding a signature, the private key with an optional
key id has to be given.
The private key can be
a L<Mojolicious::Plugin::MagicSignatures::Key> object,
a MagicKey string as described in [...] or a hashref
containing the parameters accepted by
L<Mojolicious::Plugin::MagicSignatures::Key> C<new>.

On success, the method returns the MagicEnvelope,
otherwise it returns a false value.

A MagicEnvelope can be signed multiple times.

B<This method is experimental and can change without warning!>

=head2 C<verify>

  $me->verify([['RSA...'],['RSA...','key-01']])

Verifies a signed envelope against a bunch of given public MagicKeys.
Returns true on success. In other case false.
The structure of the bunch of keys is

  [ [ MagicKey, key_id? ]* ]

If one key succeeds, the envelope is verified.

B<This method is experimental and can change without warning!>

=head2 C<to_xml>

  $me->to_xml;

Returns the MagicEnvelope as a stringified xml representation.

=head2 C<to_json>

  $me->to_json;

Returns the MagicEnvelope as a stringified json representation.

=head2 C<to_compact>

  $me->to_compact;

Returns the MagicEnvelope as a compact representation.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Base64url>,
L<Mojolicious::Plugin::MagicSignatures::Key>.

=head1 KNOWN BUGS AND LIMITATIONS

The signature is currently not working correctly!

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl.

=cut
