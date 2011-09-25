package Mojolicious::Plugin::MagicSignatures::Key;
use Mojo::Base -base;
use bytes;

use Mojolicious::Plugin::Util::Base64url;
use Digest::SHA 'sha256';

# Implement with GMP or PARI if existent
use Math::BigInt try => 'GMP,Pari';

has [qw/n d emLen/] => 0;
has e => 65537;

use constant {
  # http://www.ietf.org/rfc/rfc3447.txt
  # [Ch. 9.2 Notes 1]
  DER_MD2    => "\x30\x20\x30\x0c\x06\x08\x2a\x86\x48".
                "\x86\xf7\x0d\x02\x02\x05\x00\x04\x10",
  DER_MD5    => "\x30\x20\x30\x0c\x06\x08\x2a\x86\x48".
                "\x86\xf7\x0d\x02\x05\x05\x00\x04\x10",
  DER_SHA1   => "\x30\x21\x30\x09\x06\x05\x2b\x0e\x03".
                "\x02\x1a\x05\x00\x04\x14",
  DER_SHA256 => "\x30\x31\x30\x0d\x06\x09\x60\x86\x48".
                "\x01\x65\x03\x04\x02\x01\x05\x00\x04\x20",
  DER_SHA384 => "\x30\x41\x30\x0d\x06\x09\x60\x86\x48".
                "\x01\x65\x03\x04\x02\x02\x05\x00\x04\x30",
  DER_SHA512 => "\x30\x51\x30\x0d\x06\x09\x60\x86\x48".
                "\x01\x65\x03\x04\x02\x03\x05\x00\x04\x40"
};

# Construct a new MagicSignature object
# Needs a key (private or public)
sub new {
  my $class = shift;
  my $self;

  # MagicKey object
  if (ref $_[0] && ref $_[0] eq __PACKAGE__) {
    return $_[0];
  }

  # MagicKey in string notation
  elsif (@_ == 1) {
    my $string = shift;
    return unless $string;

    # New object from parent class
    $self = $class->SUPER::new;

    # Delete whitespace
    $string =~ tr{\t-\x0d }{}d;

    # Split MagicKey
    my ($type, $mod, $exp, $private_exp) = split(/\./, $string);

    # The key is incorrect
    if ($type ne 'RSA') {
      warn 'MagicKey is incorrectly formatted!' and return;
    };

    # RSA.modulus(n).exponent(e).private_exponent(he)?
    for ($mod, $exp, $private_exp) {
      next unless $_;
      $_ = _b64url_to_hex($_);
    };

    # Set modulus
    $self->n( $mod );

    # Set exponent
    $self->e( $exp );

    # Set private key
    $self->d( $private_exp ) if $private_exp;
  }

  # Key defined by parameters
  else {
    $self = $class->SUPER::new(@_);

    unless ($self->n || $self->d) {
      warn 'Key is not well defined.' and return;
    };

  };

  # Set emLen (octet length of modulus)
  $self->emLen( _octet_len( $self->n ) );

  return $self;
};


# Sign a message
sub sign {
  my ($self, $message) = @_;

  unless ($self->d) {
    warn 'You can only sign with a private key' and return;
  };

  my $encoded_message = _sign_emsa_pkcs1_v1_5($self, $message);

  # Append padding - although that's not defined
  #    while ((length($encoded_message) % 4) != 0) {
  #        $encoded_message .= '=';
  #    };

  return _hex_to_b64url($encoded_message);
};


# Verify a signature for a message (sig base)
sub verify {
  my ($self,
      $message,
      $encoded_message) =  @_;

  unless ($encoded_message && $message) {
    warn 'No signature or message given.' and return;
  };

  return _verify_emsa_pkcs1_v1_5(
    $self,
    $message,
    _b64url_to_hex( $encoded_message )
  );
};


# Return MagicKey-String (public only)
sub to_string {
  my $self = shift;

  my $n = $self->n;
  my $e = $self->e;

  # Convert modulus and exponent
  $_ = _hex_to_b64url($_) for ($n, $e);

  my $mkey = join('.', ( 'RSA', $n, $e ) );

  # $mkey =~ s/=+//g;

  return $mkey;
};


# Sign with emsa padding
sub _sign_emsa_pkcs1_v1_5 ($$) {
  # http://www.ietf.org/rfc/rfc3447.txt [Ch. 8.1.1]

  # key, message
  my ($K, $M) = @_;

  my $k = length($K->n);
#  my $k = $K->emLen;

#  my $EM = _emsa_encode($M, $k, 'sha-256');
  my $EM = _emsa_encode($M, $K->emLen, 'sha-256');

  return unless $EM;

  my $m  = _os2ip($EM);
  my $s  = _rsasp1($K, $m);
#  my $S  = _i2osp($s, $k);

  return $s; # $S
};


# Verify with emsa padding
sub _verify_emsa_pkcs1_v1_5 {
  # http://www.ietf.org/rfc/rfc3447.txt [Ch. 8.2.2]

  # key, message, signature
  my ($K, $M, $S) = @_;

  my $k = length( $K->n );
#  my $k = $K->emLen;

  # The length of the signature is not
  # equivalent to the length of the RSA modulus
  if (length($S) != $k) {
#  if (_octet_len($S) != $k) {
    warn('Length: '.join('-',
			 length($S),
			 $k,
			 _octet_len($S),
			 _octet_len($K->n)));
    warn 'Invalid signature.' and return;
  };

  my $s = $S;
#  my $s = _os2ip($S);
  my $m = _rsavp1($K, $s);

  return unless $m;

  my $EM_1 = _i2osp($m, $k);
  my $EM_2 = _emsa_encode($M, $k, 'sha-256');

  # Compare codes with success
  return 1 if _b64url_to_hex($EM_1) eq _b64url_to_hex($EM_2);

  # No success
  return;
};


# RSA signing
sub _rsasp1 {
  # http://www.ietf.org/rfc/rfc3447.txt [Ch. 5.2.1]

  # Key, message
  my ($K, $m) = @_;

  if ($m >= $K->n) {
    warn "message representative out of range." and return;
  };

  if ($K->n) {
    return
      Math::BigInt->new($m)->bmodpow($K->d, $K->n);
  };

  # Not implemented yet - eventually not needed
  #    elsif ($K->p && $K->q) {
  #	return;
  #    };

  return;
};


# RSA verification
sub _rsavp1 {
  # http://www.ietf.org/rfc/rfc3447.txt [Ch. 5.2.2]

  # Key, signature
  my ($K, $s) = @_;

  if ($s > (Math::BigInt->new($K->n)->bsub(1))) {
#  if ($s < (Math::BigInt->new($K->n)->bsub(1))) {
#  if (length($s) > (Math::BigInt->new($K->n)->bsub(1))) {
#    warn $s.' : ' . $K->n . ':' . length($s) . ':'.length($K->n);
    warn 'Signature representative out of range.' and return;
  };

  if ($K->n) {
    return
      Math::BigInt->new($s)->bmodpow($K->e, $K->n);
  };

  return;
};


# Create code with emsa padding (only sha-256 support)
sub _emsa_encode {
  # http://www.ietf.org/rfc/rfc3447.txt [Ch. 9.2]

  my ($M, $emLen, $hash_digest) = @_;

  # No message given
  return unless $M;

  $hash_digest ||= 'sha-256';

  # Create Hash with der padding
  my ($H, $T, $tLen);
  if ($hash_digest eq 'sha-256') {
    $H = sha256($M);  # hex?
    $T = DER_SHA256 . $H;
    $tLen = length( $T );
  }

  # Hash-value is unknown
  else {
    warn 'Hash value currently not supported.' and return;
  };

  # TODO:
  # if ($emlen < length($T) + 10) {
  #   warn "Intended encoded message length too short."
  #   return;
  # };

  # temp!
  # pad_string = chr(0xFF) * (msg_size_bits - len(encoded) - 3)
  # instead of
  # pad_string = chr(0xFF) * (msg_size_bits / 8 - len(encoded) - 3)
  #  $emLen = ($emLen + 8 - ($emLen % 8) / 8);
  #  my $PS = "\xFF" x ($emLen / 8 - $tLen - 3); # -3

  my $PS = "\xFF" x ($emLen - $tLen - 3);
  my $EM = "\x00\x01".$PS."\x00".$T;

  return $EM;
};


# Convert from octet string to bigint
sub _os2ip ($) {
  # Based on
  # http://cpansearch.perl.org/src/GBARR/Convert-ASN1-0.22/lib/Convert/ASN1.pm
  # http://cpansearch.perl.org/src/VIPUL/Crypt-RSA-1.99/lib/Crypt/RSA/DataFormat.pm

  my $os = shift;
  my $result = Math::BigInt->new(0);

  my $neg = ord($os) >= 0x80
    and $os ^= chr(255) x length($os);

  for (unpack("C*",$os)) {
    $result = ($result * 256) + $_;
  };

  return $neg ? ($result + 1) * -1 : $result;
}


# Convert from bigint to octet string
sub _i2osp {
  # Based on
  # http://cpansearch.perl.org/src/VIPUL/Crypt-RSA-1.99/lib/Crypt/RSA/DataFormat.pm

  my $num = Math::BigInt->new( shift );
  my $l = shift || 0;

  my $result = '';

  if ($l && $num > ( 256 ** $l )) {
    warn 'i2osp error.' and return;
  };

  do {
    my $r = $num % 256;
    $num = ($num - $r) / 256;
    $result = chr($r) . $result;
  } until ($num < 256);

  $result = chr($num) . $result if $num != 0;

  if (length($result) < $l) {
    $result = chr(0) x ($l - length($result)) . $result;
  };

  return $result;
};


# Returns the octet length of a given integer
sub _octet_len {
  # Based on
  # https://github.com/mozilla/django-salmon/
  #         blob/master/django_salmon/magicsigs.py
  # Round up to next byte
  # modulus_size = keypair.size()
  # msg_size_bits = modulus_size + 8 - (modulus_size % 8)
  # pad_string = chr(0xFF) * (msg_size_bits / 8 - len(encoded) - 3)
  # return chr(0) + chr(1) + pad_string + chr(0) + encoded

  my $bs = Math::BigInt->new( _bitsize( shift ) );
  my $val = $bs->badd(7)->bdiv(8);
  return $val->bfloor;
};


# Returns the bitlength of the integer
sub _bitsize ($) {
  my $int = Math::BigInt->new( shift );
  return 0 unless $int;
  return ( length( $int->as_bin ) - 2 );
};


# base64url to hex number
sub _b64url_to_hex {
  # Based on
  # https://github.com/sivy/Salmon/blob/master/lib/Salmon/
  #         MagicSignatures/SignatureAlgRsaSha256.pm
  my $num = b64url_decode( shift );
  $num = "0x" . unpack( "H*", $num );
  return Math::BigInt->from_hex( $num )->bstr;
};


# hex number to base64url
sub _hex_to_b64url {
  # https://github.com/sivy/Salmon/blob/master/lib/Salmon/
  #         MagicSignatures/SignatureAlgRsaSha256.pm

  my $num = Math::BigInt->new( shift )->as_hex;
  $num =~ s/^0x//;
  $num = ( ( ( length $num ) % 2 ) > 0 ) ? "0$num" : $num;
  $num = pack( "H*", $num );
  return b64url_encode( $num );
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::MagicSignatures::Key - MagicKey Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Plugin::MagicSignatures::Key;

  my $mkey = Mojolicious::Plugin::MagicSignatures::Key->new(<<'MKEY');
    RSA.
    mVgY8RN6URBTstndvmUUPb4UZTdwvw
    mddSKE5z_jvKUEK6yk1u3rrC9yN8k6
    FilGj9K0eeUPe2hf4Pj-5CmHww==.
    AQAB.
    Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6
    yihYetQ8jy-jZXdsZXd8V5ub3kuBHH
    k4M39i3TduIkcrjcsiWQb77D8Q==
  MKEY

=head1 DESCRIPTION

L<Mojolicious::Plugin::MagicSignatures::Key> is a plugin for
L<Mojolicious> to represent MagicKeys as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 ATTRIBUTES

=head2 C<n>

The MagicKey RSA modulus.

=head2 C<e>

The MagicKey RSA exponent. By default this value is 65537.

=head2 C<d>

The MagicKey RSA private exponent.

=head2 C<emLen>

The octet-length of C<n>.

=head1 METHODS

=head2 C<new>

The Constructor accepts MagicKeys in compact notation as
described in L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head2 C<sign>

  my $sig = $mkey->sign('This is a message');

Signs a message (if the key is a private key) and returns
the signature. The signature algorithm is based on
L<http://www.ietf.org/rfc/rfc3447.txt|Specification>.

=head2 <verify>

  if ($mkey->verify('This is a message', $sig) {
    print "The signature is okay.";
  } else {
    print "The signature is wrong!";
  };

Verifies a signature of a message based on the public
component of the key. Returns true on success, and false otherwise.

=head2 C<to_string>

  print $mkey->to_string;

Returns the public key as a string in compact notation as
described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Base64url>.
Either L<Math::BigInt::GMP> or L<Math::BigInt::Pari> are recommended.

=head1 KNOWN BUGS AND LIMITATIONS

The signing and verifification is currently not working!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
