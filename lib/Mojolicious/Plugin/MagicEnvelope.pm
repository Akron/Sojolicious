package Mojolicious::Plugin::MagicEnvelope;
use strict;
use warnings;
use Mojolicious::Plugin::MagicKey qw(b64url_encode
                                     b64url_decode);
use Mojo::Command;
use Mojo::DOM;
use Mojo::Template;
use Mojo::JSON;

our ($me_ns, @val_array);
BEGIN {
    our $me_ns     = 'http://salmon-protocol.org/ns/magic-env';
    our @val_array = qw/data data_type encoding alg sigs/;
};

# Constructor
sub new {
    my $class = shift;

    my $self = {
	alg       => 'RSA-SHA256',
	encoding  => 'base64url',
	data_type => 'text/plain',
	sigs      => [],
	signed    => 0,
	verified  => 0
    };

    # Message is me-xml:
    if ($_[0] =~ /^[\s\n]*\</) {

	my $dom = Mojo::DOM->new(xml => 1);
	$dom->parse( shift );
	
	# Succesfull extracted envelope?
	my $env = $dom->at('env');
	$env = $dom->at('provenance') unless $env;
	return if (!$env || $env->namespace ne $me_ns);

	# Retrieve and edit data
	my $data = $env->at('data');
	$self->{data_type} = $data->attrs->{type};
	$self->{data} = b64url_decode ( $data->text );
	
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
	    }
	    );
    }

    # Message is me-json as a datastructure
    elsif (ref($_[0]) && (ref($_[0]) eq 'HASH')) {
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

	warn 'Unknown parameters: '.join(',', %$env)
	    if keys %$env;
    }

    # Message is me as a compact string
    elsif ($_[0] =~ /\.YmFzZTY0dXJs\./) {
	my ($key_id, $sig,
	    $data, $data_type, $encoding, $alg) =
	    split(/\./, shift );

	for ($key_id, $sig,
	     $data, $data_type, $encoding, $alg) {
	    $_ = b64url_decode( $_ ) if $_;
	};

	$self->{data}      = $data;
	$self->{data_type} = $data_type;
	$self->{encoding}  = $encoding if $encoding;
	$self->{alg}       = $alg      if $alg;

	for ($self->{sigs}->[0]) {
	    $_->{value}     = $sig;
	    $_->{key_id}    = $key_id if $key_id;
	    $self->{signed} = 1;
	};
    }

    # The format is not supported
    else {
	warn('Everything unknown');
	return;
    };

    # bless me instance
    return bless $self, $class;
};

# sign magic envelope instance
sub sign {
    my $self = shift;
    my %param = %{ shift(@_) };

    # Regarding key id:
    # "If the signer does not maintain individual key_ids,
    #  it SHOULD output the base64url encoded representation
    #  of the SHA-256 hash of public key's application/magic-key
    #  representation."

    return $self unless $param{key};

    my $magic_sig = Mojolicious::Plugin::MagicKey->new($param{key});

    unless ($magic_sig && $magic_sig->d) {
	warn 'Private key is not valid';
	return $self;
    };
    
    # Get signature base string
    $self->{sig_base} = _sig_base( $self->{data},
				   $self->{data_type} );

    # Compute signature for base string
    my $sig = $magic_sig->sign( $self->{sig_base} );

    unless ($sig) {
	warn 'Unable to sign message';
	return $self;
    };

    # Sign envelope
    my %sig = ( value => $sig );
    $sig{key_id} = $param{key_id} if exists $param{key_id};
    push(@{$self->{sigs}}, \%sig );

    # Declare envelope as signed
    $self->{signed} = 1;

    # Return envelope
    return $self;
};

# Is the me signed?
sub signed {

    # There is no specific key_id requested
    return $_[0]->{signed} unless $_[1];

    # Check for specific key_id
    foreach my $sig (@{ $_[0]->{sigs} }) {
	return 1 if $sig->{key_id} eq $_[1];
    };

    # Envelope is not signed
    return 0;
};

# return the data string
sub data {
    return $_[0]->{data};
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

    my $me_templ ='magicenvelope.xml.ep';

    my $cmd = Mojo::Command->new;

#    warn('CMD: '.$cmd);
#    my $test = $cmd->get_data(
#	$me_templ,
#	__PACKAGE__);
#    use Data::Dumper;
#    my $value = Data::Dumper::Dumper($test).'!!!';
#    die '*'.$value.'*';

    my $template = Mojo::Command->new->get_data(
	$me_templ,
	__PACKAGE__);

#    die "Error" unless $template;

# Todo:
#    $self->log->error(qq{Template not found: $me_templ!})
#	and return unless $template;
    
    return Mojo::Template->new->render($template, $self);
};

# Return em-compact string
sub to_compact {
    my $self = shift;

    # The me has to be signed
    return unless $self->{signed};

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

    # Create new datastructure
    my %new_em = (
	alg       => $self->{alg},
	encoding  => $self->{encoding},
	data_type => $self->{data_type},
	data      => b64url_encode( $self->{data} ),
	sigs      => []
	);

    # loop through signatures
    foreach my $sig ( @{ $self->{sigs} } ) {
	my %sig = ( value => b64url_encode( $sig->{value} ) );
	$sig{key_id} = $sig->{key_id};
	push( @{ $new_em{sigs} }, \%sig );
    };

    # Return json-string
    return Mojo::JSON->new->encode(\%new_em);
};

# encode urlsafe
sub _b64_enc {
    shift; #me
    return b64url_encode( $_[0] );
};

# encode urlsafe and indent
sub _b64_enc_ind {
    shift; # me
    my $val =  b64url_encode( $_[0] );
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

    my $sig_base = join('.', $data, $data_type, $encoding, $alg);

    # delete all equal signs.
    $sig_base =~ s/=//sg;

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

Mojolicious::Plugin::MagicEnvelope - MagicEnvelope Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Plugin::MagicEnvelope;

  my $me = Mojolicious::Plugin::MagicEnvelope->new(
             {
               data => 'Some arbitrary string.',
               data_ype => 'text/plain'
             }
           );

  $me = Mojolicious::Plugin::MagicEnvelope->new(<<'MEXML');
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

  if ($me->verified > 0) {
    print $me->data, " is verified!\n";
  };


=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicEnvelope> is a plugin for L<Mojolicious>
to work with Magic Envelopes as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 METHODS

=head2 C<new>

The L<Mojolicious::Plugin::MagicEnvelope> constructor accepts
magicenvelope data in various formats.

It accepts magic envelopes in the XML format or an
XML document including an magic envelope C<provenance> element.

  Mojolicious::Plugin::MagicEnvelope->new(<<'MEXML');
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

  Mojolicious::Plugin::MagicEnvelope->new({
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

  Mojolicious::Plugin::MagicEnvelope->new(<<'MECOMPACT');
    bXktMDE=.S1VqYVlIWFpuRGVTX3l4S09CcWdjRVFDYVlu
    ZkI5Ulh4dmRFSnFhQW5XUmpBUEJqZUM0b0lReER4d0IwW
    GVQZDhzWHAxN3oybWhpTk1vNHViNGNVOVE9PQ==.U29tZ
    SBhcmJpdHJhcnkgc3RyaW5nLg.dGV4dC9wbGFpbg.YmFz
    ZTY0dXJs.UlNBLVNIQTI1Ng
  MECOMPACT


=head1 ATTRIBUTES

=head2 C<data>

  $me->data;

The decoded data folded in the magic envelope.

=head2 C<dom>

  $me->dom;

The L<Mojo::DOM> object of the decoded data,
if the magic envelope contains XML.

=head1 METHODS

=head2 C<sign>

  $me->sign( { key_id => ..., key => ...} )
     ->sign( 'RSA.hgfrhvb...' )
     ->sign( Mojolicious::Plugin::MagicKey->new( ... ) );

The sign method adds a signature to the magic envelope.
The private key for signing can be a hash reference containing a
C<key> and optionally a C<key_id>, a L<Mojolicious::Plugin::MagicKey>
object or a magic key string as described in [...].

The method returns the magic envelope. A magic
envelope can be signed multiple times.

B<This method is experimental and can change without warning!>

=head2 C<signed>

  if ($me->signed) {
    print "Magic Envelope is signed.\n";
  }

Returns C<true> when the magic envelope is signed.
Accepts optionally a C<key_id> and returns true, if the
magic envelope was signed with this key.

B<This method is experimental and can change without warning!>

=head2 C<verified>

  if ($me->verified > 0) {
    print "Signature is verified.\n";
  }
  $me->verified({ key_id => ...,
                  key    => ... });

Verifies the signature of a magic envelope.

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
L<Mojolicious::Plugin::MagicKey>,
L<Mojolicious::Plugin::Webfinger>.

=head1 KNOWN BUGS AND LIMITATIONS

The signature is currently not working correctly!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl.

=cut
