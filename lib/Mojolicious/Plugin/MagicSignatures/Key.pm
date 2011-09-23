package Mojolicious::Plugin::MagicSignatures::Key;
use Mojo::Base -base;

use Mojolicious::Plugin::Util::Base64url;
use Digest::SHA qw(sha256);

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

    # Is a magic-key:
    if (ref $_[0] && ref $_[0] eq __PACKAGE__) {
	return $_[0];
    }

    # Is a Magic Key in string notation
    elsif (@_ == 1) {
	my $string = shift;

	$self = $class->SUPER::new;

	# Delete whitespace
	$string =~ s/\s+//mg;

	# Split MagicKey
	my ( $type, $mod, $exp, $private_exp )
	    = split(/\./, $string);
	
	# The key is incorrect
	if ($type ne 'RSA') {
	    warn 'Magic Key is incorrect formatted!';
	    return;
	}

	# The key is correct
	else {
	    # RSA.modulus(n).exponent(e).private_exponent(he)?
	    for ($mod, $exp, $private_exp) {
		next unless $_;
		$_ = b64url_decode($_);
		$_ = "0x" . unpack "H*", $_;
		$_ = Math::BigInt->from_hex($_)->bstr;
	    };
	    
	    $self->n( $mod );
	    $self->e( $exp );

	    # Private Key
	    if ($private_exp) {
		$self->d( $private_exp );
	    };
	};
    }

    # Key defined by parameters
    else {
	$self = $class->SUPER::new(@_);

	if (!$self->n && !$self->d) {
	    warn 'Key is not well defined.';
	    return;
	};

    };

    $self->emLen( _octet_len( $self->n ) );

    return $self;
};

# Sign a message
sub sign {
    my $self = shift;
    my $message = shift;
    
    warn 'You can only sign with a private key'
	and return unless $self->d;
    
    my $encoded_message = _sign_emsa_pkcs1_v1_5($self, $message);

    # From: https://github.com/sivy/Salmon/
    for ($encoded_message) {
	$_ = $_->as_hex;
	$_ =~ s/^0x//;
	$_ = ( ( ( length $_ ) % 2) > 0 ) ? "0$_" : $_;
	$_ = pack( "H*", $_ );
	$_ = b64url_encode( $_ );
    };

    # Append padding - although that's not defined
#    while ((length($encoded_message) % 4) != 0) {
#        $encoded_message .= '=';
#    };

    return $encoded_message;
};

# Verify a signature for a message
sub verify {
    my $self            = shift;
    my $message         = shift; # basestring!
    my $encoded_message =  shift;

    # From: https://github.com/sivy/Salmon/
#    for ($encoded_message) {
#	$_ = b64url_decode($_);
#	$_ = "0x".unpack( "H*", $_ );
#	$_ = Math::BigInt->from_hex($_); # ->bstr;
#    };

    return _verify_emsa_pkcs1_v1_5($self,
				   $message,
				   $encoded_message);
};

# Return MagicKey-String (public only)
sub to_string {
    my $self = shift;

    my $n = $self->n;
    my $e = $self->e;

    # https://github.com/sivy/Salmon/blob/master/lib/Salmon/
    #         MagicSignatures/SignatureAlgRsaSha256.pm
    foreach ($n, $e) {
	my $hex = Math::BigInt->new($_)->as_hex;
	$hex =~ s/^0x//;
	$hex = ( ( length( $hex ) % 2 ) > 0 ) ? "0$hex" : $hex;
	$_ = pack "H*", $hex;
    };
    
    my $mkey = join('.',
		    'RSA',
		    b64url_encode( $n ),
		    b64url_encode( $e ) );
#    $mkey =~ s/=+//g;
    return $mkey;
};


sub _sign_emsa_pkcs1_v1_5 ($$) {
    # http://www.ietf.org/rfc/rfc3447.txt [Ch. 8.1.1]
    my ($K, $M) = @_;

    my $k = $K->emLen;

    my $EM = _emsa_encode($M, $k, 'sha-256');

    return 0 unless $EM;

#      If the encoding operation outputs "message too long," output
#      "message too long" and stop.  If the encoding operation outputs
#      "intended encoded message length too short," output "RSA modulus
#      too short" and stop.

    my $m  = _os2ip($EM);
    my $s  = _rsasp1($K, $m);
    my $S  = _i2osp($s, $k);
    my $ES = Math::BigInt->new($s);

    return $ES;
};

sub _verify_emsa_pkcs1_v1_5 {
    # http://www.ietf.org/rfc/rfc3447.txt [Ch. 8.2.2]
    my ($K, $M, $S) = @_;
    # key, message, signature

    my $k = $K->emLen;

    if (length($S) != $k) {
	warn "invalid signature";
	warn(length($S).':'.$k);
	return 0;
    };

    my $s = _os2ip($S);
    my $m = _rsavp1($K, $s);

    # If RSAVP1 outputs "signature representative out of range,"
    # output "invalid signature" and stop.

    my $EM_1 = _i2osp($m, $k);

    # If I2OSP outputs "integer too large," output "invalid
    # signature" and stop.

    my $EM_2 = _emsa_encode($M, $k, 'sha-256');

    # If the encoding operation outputs "message too long," output
    # "message too long" and stop.  If the encoding operation outputs
    # "intended encoded message length too short," output "RSA modulus
    # too short" and stop.

    return 1 if ($EM_1 eq $EM_2);
    return 0;

    # Note.  Another way to implement the signature verification operation
    # is to apply a "decoding" operation (not specified in this document)
    # to the encoded message to recover the underlying hash value, and then
    # to compare it to a newly computed hash value.  This has the advantage
    # that it requires less intermediate storage (two hash values rather
    # than two encoded messages), but the disadvantage that it requires
    # additional code.
};

sub _rsasp1 {
    # http://www.ietf.org/rfc/rfc3447.txt [Ch. 5.2.1] 
    my ($K, $m) = @_;

    if ($m > $K->n) {
	warn "message representative out of range.";
	return;
    };

    if ($K->n) {
	return Math::BigInt->new($m)
	                   ->bmodpow($K->d, $K->n);
    };

    # Not implemented yet
    # Eventually not needed
#    elsif ($K->p && $K->q) {
#	return;
#    };
    
    return 0;
};

sub _rsavp1 {
    # http://www.ietf.org/rfc/rfc3447.txt [Ch. 5.2.2]
    my ($K, $s) = @_;

    if ($s > ($K->n->bsub(1))) {
	warn "signature representative out of range";
	warn $s.':'.$K->n;
	return 0;
    };

    return Math::BigInt->new($s)->bmodpow($K->e, $K->n);
};

sub _emsa_encode {
    # http://www.ietf.org/rfc/rfc3447.txt [Ch. 9.2]
    my ($M, $emLen, $hash_digest) = @_;

    $hash_digest ||= 'sha-256';

#    warn('M: --->',$M,"<---\n\n");

    my ($H, $T, $tLen);

    if ($hash_digest eq 'sha-256') {
	$H = sha256($M);  # hex?
#	$H = Digest::SHA->new('sha-256')->add($M)->digest;  # hex?
	$T = DER_SHA256 . $H;
	$tLen = length( $T );
    }

    # Hash-value is unknown
    else {
	warn 'Unsupported hash-value.';
    };

#    warn('H: '.b64url_encode($H)."<---\n\n");
#    warn('T: '.b64url_encode($T)."<---\n\n");

    # TODO:
    # $self->error( "Intended encoded message length 
    #                too short.", \$M )
    #    if $emlen < length($T) + 10;


# pad_string = chr(0xFF) * (msg_size_bits - len(encoded) - 3)
# instead of
# pad_string = chr(0xFF) * (msg_size_bits / 8 - len(encoded) - 3) 

#    my $PS = "\xFF" x ($emLen - $tLen - 3); # -3 

    # temp!
#    $emLen = ($emLen + 8 - ($emLen % 8) / 8);

    my $PS = "\xFF" x ($emLen - $tLen - 3); # -3 

#    warn('PS: '.b64url_encode($PS)."<---\n\n");

    # \x00
    my $EM = "\x00\x01".$PS."\x00".$T;

#    warn('EMSA: '.b64url_encode($EM)."<---\n\n");

    # Encoded Message:
    return $EM;
};

# Convert from octet string to bigint
sub _os2ip ($) {
    # http://cpansearch.perl.org/src/GBARR/Convert-ASN1-0.22/lib/Convert/ASN1.pm
    # http://cpansearch.perl.org/src/VIPUL/Crypt-RSA-1.99/lib/Crypt/RSA/DataFormat.pm

    my $os = shift;
    my $result = Math::BigInt->new(0);

    my $neg = ord($os) >= 0x80
      and $os ^= chr(255) x length($os);

    for (unpack("C*",$os)) {
      $result = ($result * 256) + $_;
    }

    return $neg ? ($result + 1) * -1 : $result;
}

# Convert from bigint to octet string
sub _i2osp {
    # http://cpansearch.perl.org/src/VIPUL/Crypt-RSA-1.99/lib/Crypt/RSA/DataFormat.pm
    my $num = Math::BigInt->new( shift ); 
    my $l = shift || 0;

    my $result = '';

    return if ($l && $num > ( 256 ** $l ));

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

    # https://github.com/mozilla/django-salmon/
    #  blob/master/django_salmon/magicsigs.py
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

sub _warn {
    my $self = shift;

    # log established
    if ($self->log) {
	$self->log->warn($_[0]);
    }

    # No log established
    else {
	warn $_[0];
    };

    return;
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
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>

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
described in [...].

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

=head2 C<to_string>

  print $mkey->to_string;

Returns the string in compact notation as described in [...].

=head1 FUNCTIONS

L<Mojolicious::Plugin::MagicKey> implements the following functions,
that can be imported.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Base64url>.
Either L<Math::BigInt::GMP> or L<Math::BigInt::Pari> are recommended.


=head1 KNOWN BUGS AND LIMITATIONS

The signing and verifification is currently not working
correctly!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
