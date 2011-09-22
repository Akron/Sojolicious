package Mojolicious::Plugin::MagicSignatures::Envelope;
use Mojo::Base '-base';
use Mojolicious::Plugin::Util::Base64url;
use Mojo::Command;
use Mojo::DOM;
use Mojo::Template;
use Mojo::JSON;

has 'data';
has alg       => 'RSA-SHA256';
has encoding  => 'base64url';
has data_type => 'text/plain';


use constant ME_NS => 'http://salmon-protocol.org/ns/magic-env';

my @val_array = qw/data data_type encoding alg sigs/;

# Constructor
sub new {
    my $class = shift;

    my $self = $class->SUPER::new;
    $self->{sigs} = [];

    # Message is me-xml:
    if ($_[0] =~ /^[\s\n]*\</) {

	my $dom = Mojo::DOM->new(xml => 1);
	$dom->parse( shift );
	
	# Succesfull extracted envelope?
	my $env = $dom->at('env');
	$env = $dom->at('provenance') unless $env;
	return if (!$env || $env->namespace ne ME_NS);

	# Retrieve and edit data
	my $data = $env->at('data');
	$self->data_type( $data->attrs->{type} );
	$self->data( b64url_decode ( $data->text ) );
	
	# Check algorithm
	return if ($env->at('alg') &&
		   ($env->at('alg')->text ne 'RSA-SHA256'));
	
	# Check encoding
	return if ($env->at('encoding') && 
		   ($env->at('encoding')->text ne 'base64url'));
	
	# Retrieve signature
	$env->find('sig')->each(
	    sub {
		my %sig = ( value => b64url_decode( $_->text ) );
		
		$sig{key_id} = $_->attrs->{key_id}
		  if exists $_->attrs->{key_id};

		push( @{ $self->{sigs} }, \%sig );

		$self->{signed} = 1;
	    });
    }

    # Message is me-json as a datastructure
    elsif (ref $_[0] && (ref $_[0] eq 'HASH')) {
	my $env = shift;

	foreach my $v (@val_array) {
	    $self->{$v} = delete $env->{$v} if exists $env->{$v};
	};

	if ($self->{sigs}->[0]) {
	    $self->{signed} = 1;
	};

	# Unknown parameters
	warn 'Unknown parameters: '.join(',', %$env)
	    if keys %$env;
    }

    # Message is me-json as a string
    elsif ($_[0] =~ /^[\s\n]*\{/) {
	my $json = Mojo::JSON->new;
	my $env = $json->decode( shift );

	foreach my $v (@val_array) {
	    $self->{$v} = $env->{$v};
	};

	if ($self->{sigs}->[0]) {
	    $self->{signed} = 1;
	};

	warn 'Unknown parameters: ' . join(',', %$env)
	    if keys %$env;
    }

    # Message is me as a compact string
    elsif ($_[0] =~ /\.YmFzZTY0dXJs\./) {

	my @val;
	foreach (@val = split(/\./, shift ) ) {
	    $_ = b64url_decode( $_ ) if $_;
	};

	for ($self->{sigs}->[0]) {
	    $_->{key_id}    = $val[0] if defined $val[0];
	    $_->{value}     = $val[1];
	    $self->{signed} = 1;
	};

	$self->data($val[2])      if $val[2];
	$self->data_type($val[3]) if $val[3];
	$self->encoding($val[4])  if $val[4];
	$self->alg($val[5])       if $val[5];
    }

    # The format is not supported
    else {
	return;
    };

    # bless me instance
    return $self;
};

# sign magic envelope instance
sub sign {
    my $self   = shift;
    my $key_id = shift;
    my $val    = shift;

    # Regarding key id:
    # "If the signer does not maintain individual key_ids,
    #  it SHOULD output the base64url encoded representation
    #  of the SHA-256 hash of public key's application/magic-key
    #  representation."

    # A valid key is given
    if ($val) {

	# Set key based on parameters
	my @param = (
	    ref $val ?
	    ( ref $val eq 'HASH' ? %{ $val } : $val )
	    : $val);
	
	my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new( @param );

	return undef unless ($mkey && $mkey->d);

	# Get signature base string
	$self->{sig_base} = _sig_base( $self->{data},
				       $self->{data_type} );
	
	# Compute signature for base string
	my $msig = $mkey->sign( $self->{sig_base} );
	
	return undef unless $msig;
	
	# Sign envelope
	my %msig = ( value => $msig );
	
	$msig{key_id} = $key_id if defined $key_id;
	
	# Push signature
	push(@{$self->{sigs}}, \%msig );
	
	# Declare envelope as signed
	$self->{signed} = 1;
	
	# Return envelope
	return $self;
    };


    # Get signature:
    my @sigs = @{ $self->{sigs} };

    # No key_id given
    if (!$key_id) {

	foreach (@sigs) {
	    if (!exists $_->{key_id}) {
		return $_->{value};
	    };
	};

	return $sigs[0]->{value};
    }

    # Key is given
    else {
	my $default;
	foreach (@sigs) {
	    if (defined $_->{key_id}) {
		if ($_->{key_id} eq $key_id) {
		    return $_->{value};
		};
	    } else {
		$default = $_->{value};
	    };
	};
	return $default;
    };

    return undef;
};


# Is the me signed?
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

# return the data as a MojoDOM if it is xml
sub dom {
    my $self = shift;

    # There is already a DOM instantiation
    return $self->{dom} if exists $self->{dom};

    # Create new DOM instantiation
    my $dom = Mojo::DOM->new;
    if ($self->{data_type} =~ /xml/) {
	$dom->parse( $self->{data} );
    };

    # Return DOM instantiation (Maybe empty)
    return ($self->{dom} = $dom);
};

# Return em-xml string
sub to_xml {
    my $self = shift;

    # The me has to be signed
    return unless $self->{signed};

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

    # Use last signature for serialization
    my $sig = $self->{sigs}->[ $#{ $self->{sigs} } ];

    $self->{sig_base} = _sig_base(
	$self->{data},
	$self->{data_type}
	) unless exists $self->{sig_base};

    return join( '.',
		 b64url_encode( $sig->{key_id} ),
		 b64url_encode( $sig->{value} ),
		 $self->{sig_base} );
};

# Return em-json string
sub to_json {
    my $self = shift;

    return '{}' unless defined $self->data;

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

# encode urlsafe
sub _b64_enc {
    return b64url_encode( $_[1] );
};

# encode urlsafe and indented
sub _b64_enc_ind {
    my $val =  b64url_encode( $_[1] );
    return '    ' . join( "\n    ", ( unpack '(A60)*', $val ) );
};

# create signature base string
sub _sig_base {
    my $data      = b64url_encode( shift );

    # data_type - default "text/plain"
    my $data_type = $_[0] ? b64url_encode( shift ) : 'dGV4dC9wbGFpbg';

    # encoding  - default "base64url"
    my $encoding  = $_[0] ? b64url_encode( shift ) : 'YmFzZTY0dXJs';

    # alg       - default "RSA-SHA256"
    my $alg       = $_[0] ? b64url_encode( shift ) : 'UlNBLVNIQTI1Ng';

    my $sig_base = join('.',
			$data,
			$data_type,
			$encoding,
			$alg);

    # delete all equal signs
    # maybe that's wrong and it should say s/=+$//sg; ?
    $sig_base =~ s/=+$//sg;

    return $sig_base;
};

1;

__DATA__

@@ magicenvelope.xml.ep
% my $me = shift;
% my $start_tag = 'env';
% if ($me->{embed}) {
% $start_tag = 'provenance';
<% } else { =%>
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
% }
<me:<%= $start_tag %> xmlns:me="http://salmon-protocol.org/ns/magic-env">
  <me:data<% if (exists $me->{'data_type'}) { =%>
<%= ' ' %>type="<%== $me->{'data_type'} %>"
<% } =%>
>
<%= $me->_b64_enc_ind( $me->{'data'} ) %>
  </me:data>
  <me:encoding><%= $me->{'encoding'} %></me:encoding>
  <me:alg><%= $me->{'alg'} %></me:alg>
% foreach my $sig (@{$me->{'sigs'}}) {
  <me:sig
<% if (exists $sig->{'key_id'}) { =%>
<%= ' ' %>key_id="<%== $sig->{'key_id'} %>"
<% } =%>
>
<%= $me->_b64_enc_ind($sig->{'value'}) %>
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

  $me->sign('key' => 'RSA.vsd...');

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

=head2 C<dom>

  my $dom = $me->dom;

The L<Mojo::DOM> object of the decoded data,
if the magic envelope contains XML.

=head2 C<encoding>

  $me->encoding;

The encoding of the MagicEnvelope. Defaults to 'base64url'.

=head2 C<signed>

  if ($me->signed) {
    print "Magic Envelope is signed.\n";
  }

Returns C<true> when the MagicEnvelope is signed at least once.
Accepts optionally a C<key_id> and returns true, if the
MagicEnvelope was signed with this key.

B<This attribute is experimental and can change without warning!>

=head1 METHODS

=head2 C<new>

The L<Mojolicious::Plugin::MagicSignatures::Envelope> constructor accepts
magicenvelope data in various formats.

It accepts magic envelopes in the XML format or an
XML document including an magic envelope C<provenance> element.

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

Additionally it accepts magic envelopes in the JSON notation.

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

The constructor also accepts magic envelopes as a datastructure
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

Finally the constructor accepts magic envelopes in the compact
notation.

  Mojolicious::Plugin::MagicSignatures::Envelope->new(<<'MECOMPACT');
    bXktMDE=.S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVlu
    ZkI5Ulh4dmRFSnFhQW5XUmpBUEJqZUM0b0lReER4d0IwW
    GVQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ==.U29tZ
    SBhcmJpdHJhcnkgc3RyaW5nLg.dGV4dC9wbGFpbg.YmFz
    ZTY0dXJs.UlNBLVNIQTI1Ng
  MECOMPACT

=head2 C<sign>

  $me->sign( 'my-01' => 'RSA.hgfrhvb ...' )
     ->sign( undef   => 'RSA.hgfrhvb ...' );

  my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new( 'RSA.hgfrhvb ...' )
  $me->sign( undef => $mkey );

  my $sig = $me->sign('my-01');
  my $sig = $me->sign;

The sign method gets or adds a signature to the MagicEnvelope.

For adding a signature, two parameters are necessary: the key id
and the private key for signing.
The private key for signing can be
a L<Mojolicious::Plugin::MagicSignatures::Key>
object, a MagicKey string as described in [...] or a hashref
containing the parameters accepted by 
L<Mojolicious::Plugin::MagicSignatures::Key> C<new>.
To sign with a default key, use an undefined key id.

On success, the method returns the MagicEnvelope, otherwise it
returns undef.
A MagicEnvelope can be signed multiple times.

For retrieving a specific signature, pass the key id.
If a signature with the given key id is found, the signature
value is returned. If it is not found, the default signature
is returned. If no key id is given, the default signature value
is returned. If no matching signature can be found, undef is returned.

B<This method is experimental and can change without warning!>

=head2 C<to_xml>

  $me->to_xml;

Returns the magic envelope as a stringified xml representation.

=head2 C<to_json>

  $me->to_json;

Returns the magic envelope as a stringified json representation.

=head2 C<to_compact>

  $me->to_compact;

Returns the magic envelope as a compact representation.

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::Util::Base64url>,
L<Mojolicious::Plugin::MagicSignatures::Key>.

=head1 KNOWN BUGS AND LIMITATIONS

The signature is currently not working correctly!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl.

=cut
