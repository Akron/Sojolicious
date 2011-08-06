package Mojolicious::Plugin::MagicKey;
use strict;
use warnings;
use Mojo::Base -base;

use Math::BigInt;
use MIME::Base64;
use Digest::SHA qw(sha256);
use Exporter 'import';
our @EXPORT_OK = qw(b64url_encode
                    b64url_decode);

has [qw/n d emLen/] => 0;
has e => 65537;
# has ns => sub { 'http://salmon-protocol.org/ns/magic-key' };

# Construct a new MagicSignature object
# Needs a key (private or public)
sub new {
    my $class = shift;
    my $self;

    # Is a magic-key:
    if (length($_[0]) > 1) {
	my $string = shift;

	$self = $class->SUPER::new;

	my ( $type, $mod, $exp, $private_exp )
	    = split('\.', $string);
	
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
		$_ = "0x".unpack "H*", $_;
		$_ = Math::BigInt->from_hex($_);
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

    my $encoded_message = _sign_emsa_pkcs1_v1_5($self, $message );

    # From: https://github.com/sivy/Salmon/
    for ($encoded_message) {
	$_ = $_->as_hex;
	$_ =~ s/^0x//;
	$_ = ( ( length $_ ) % 2 > 0 ) ? "0$_" : $_;
	$_ = pack( "H*", $_ );
	$_ = b64url_encode($_);
    };

    # Append padding - although that's not defined
    while ((length($encoded_message) % 4) != 0) {
        $encoded_message .= '=';
    };

    return $encoded_message;
};

# Verify a signature for a message
sub verify {
    my $self = shift;
    my $message = shift;
    my $encoded_message =  shift;

    # From: https://github.com/sivy/Salmon/
    for ($encoded_message) {
	$_ = b64url_decode($_);
	$_ = "0x".unpack( "H*", $_ );
	$_ = Math::BigInt->from_hex($_); # ->bstr;
    };

#    warn('verify: '.$encoded_message);

    return _verify_emsa_pkcs1_v1_5($self,
				   $message,
				   $encoded_message);
};

# Return MagicKey-String
sub to_string {
    my $self = shift;
    my $mkey = join('.',
		    'RSA',
		    b64url_encode( $self->n ),
		    b64url_encode( $self->e ) );
    $mkey =~ s/=+//g;
    return $mkey;
};

# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 9.2 Notes 1
#sub _der_md2    { "\x30\x20\x30\x0c\x06\x08\x2a\x86\x48".
#	          "\x86\xf7\x0d\x02\x02\x05\x00\x04\x10"     };
#sub _der_md5    { "\x30\x20\x30\x0c\x06\x08\x2a\x86\x48".
#                  "\x86\xf7\x0d\x02\x05\x05\x00\x04\x10"     };
#sub _der_sha1   { "\x30\x21\x30\x09\x06\x05\x2b\x0e\x03".
#                  "\x02\x1a\x05\x00\x04\x14"                 };
sub _der_sha256 { "\x30\x31\x30\x0d\x06\x09\x60\x86\x48".
                  "\x01\x65\x03\x04\x02\x01\x05\x00\x04\x20" };
#sub _der_sha384 { "\x30\x41\x30\x0d\x06\x09\x60\x86\x48".
#                  "\x01\x65\x03\x04\x02\x02\x05\x00\x04\x30" };
#sub _der_sha512 { "\x30\x51\x30\x0d\x06\x09\x60\x86\x48".
#                  "\x01\x65\x03\x04\x02\x03\x05\x00\x04\x40" };


# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 8.1.1
sub _sign_emsa_pkcs1_v1_5 {
    my ($K, $M) = @_;

    my $k = $K->emLen;

    my $EM = _emsa_encode($M, $k, 'sha-256');

#      If the encoding operation outputs "message too long," output
#      "message too long" and stop.  If the encoding operation outputs
#      "intended encoded message length too short," output "RSA modulus
#      too short" and stop.

    my $m = _os2ip($EM);
    my $s = _rsasp1($K, $m);
    my $S = _i2osp($s, $k);
    my $ES = Math::BigInt->new($s);

    return $ES;
};

# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 8.2.2
sub _verify_emsa_pkcs1_v1_5 {
    my ($K, $M, $S) = @_;

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

# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 5.2.1 
sub _rsasp1 {
    my ($K, $m) = @_;

    if ($m > $K->n) {
	warn "message representative out of range.";
	return;
    };

    my $s;
    if ($K->n) {
	$s = Math::BigInt->new($m)->bmodpow($K->d, $K->n)
    }

    # Not implemented yet
    # Eventually not needed
#    elsif ($K->p && $K->q) {
#	return;
#    };
    
    return $s;
};

# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 5.2.2
sub _rsavp1 {
    my ($K, $s) = @_;

    if ($s > ($K->n->bsub(1))) {
	warn "signature representative out of range";
	warn $s.':'.$K->n;
	return 0;
    };

    return Math::BigInt->new($s)->bmodpow($K->e, $K->n);
};

# http://www.ietf.org/rfc/rfc3447.txt
# Ch. 9.2
sub _emsa_encode {
    my ($M, $emLen, $hash_digest) = @_;

    $hash_digest ||= 'sha-256';

#    warn('M: --->',$M,"<---\n\n");

    my ($H, $T, $tLen);
    if ($hash_digest eq 'sha-256') {
	$H = sha256($M);  # hex?
	$T = _der_sha256 . $H;
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

    my $PS = "\xFF" x ($emLen - $tLen - 3); # -3 

#    warn('PS: '.b64url_encode($PS)."<---\n\n");

    # \x00
    my $EM = "\x01".$PS."\x00".$T;

#    warn('EMSA: '.b64url_encode($EM)."<---\n\n");

    # Encoded Message:
    return $EM;
};

# http://cpansearch.perl.org/src/GBARR/Convert-ASN1-0.22/lib/Convert/ASN1.pm
# Convert from an octet string to a bigint
sub _os2ip {
    my $os = shift;
    my $result = Math::BigInt->new(0);

    my $neg = ord($os) >= 0x80
      and $os ^= chr(255) x length($os);

    for (unpack("C*",$os)) {
      $result = ($result * 256) + $_;
    }
    return $neg ? ($result + 1) * -1 : $result;
}

# http://cpansearch.perl.org/src/GBARR/Convert-ASN1-0.22/lib/Convert/ASN1.pm
# Convert from a bigint to an octet string
sub _i2osp {
    my $num = Math::BigInt->new( shift );
    my $neg = $num < 0 and $num = abs($num+1);

    my $result = '';

    while($num != 0) {
        my $r = $num % 256;
        $num = ($num - $r) / 256;
        $result .= chr( $r );
    }

    $result ^= chr(255) x length($result) if $neg;

    return scalar reverse $result;
};

# Returns the octet length of a given integer
sub _octet_len {
    my $bs = Math::BigInt->new( _bitsize( shift ) );
    my $val = ($bs + 7) / 8;
    return $val->bfloor;
};

# Returns the bitlength of the integer
sub _bitsize {
    my $x = Math::BigInt->new( shift );
    return ( length( $x->as_bin ) - 2 );
};

# Returns the b64 urlsafe encoding of a string
sub b64url_encode {
    my $v = shift;
    return '' unless $v;

    utf8::encode $v if utf8::is_utf8 $v;
    $v = encode_base64($v, '');
    $v =~ tr{+/}{-_};

    $v =~ tr{\t-\x0d }{}d;

    # No trailing paddings follows spec:
    # Salmon protocol - rfc.section.3.1
    # $v =~ s/=+$//s;
    return $v;
};

# Returns the b64 urlsafe decoded string
sub b64url_decode {
    my $v = shift;
    return '' unless $v;
    $v =~ tr{-_}{+/};

    if (my $padding = (length($v) % 4)) {
	$v .= '=' x (4 - $padding);
    };
    
    return decode_base64($v);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::MagicKey - MagicKey Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Plugin::MagicKey;

  my $mkey = Mojolicious::Plugin::MagicKey->new(<<'MKEY');
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

L<Mojolicious::Plugin::MagicKey> is a plugin for L<Mojolicious>
to represent MagicKeys as described in
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

=head2 C<b64url_encode>

  print b64url_encode('This is a message');

Encodes a string 64-based with URL safe characters.

=head2 C<b64url_encode>

  print b64url_decode('VGhpcyBpcyBhIG1lc3NhZ2U=');

Decodes a 64-based string with URL safe characters.

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 KNOWN BUGS AND LIMITATIONS

The signing and verifification is currently not working
correctly!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
