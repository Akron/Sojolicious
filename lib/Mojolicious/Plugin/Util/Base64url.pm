package Mojolicious::Plugin::Util::Base64url;
use Mojo::Base -strict;

use Mojo::Util qw/b64_encode b64_decode/;

use Exporter 'import';
our @EXPORT = qw(b64url_encode
                 b64url_decode);

# Returns the b64 urlsafe encoding of a string
sub b64url_encode ($;$) {
  my $v = shift;
  my $p = defined $_[0] ? shift : 1;

  return '' unless $v;

  utf8::encode $v if utf8::is_utf8 $v;
  $v = b64_encode($v, '');
  $v =~ tr{+/}{-_};
  $v =~ tr{\t-\x0d }{}d;

  # Trim padding or not
  $v =~ s/\=+$// unless $p;

  return $v;
};

# Returns the b64 urlsafe decoded string
sub b64url_decode ($) {
  my $v = shift;
  return '' unless $v;

  $v =~ tr{-_}{+/};

  # Add padding
  if (my $padding = (length($v) % 4)) {
    $v .= chr(61) x (4 - $padding);
  };

  return b64_decode($v);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Util::Base64url - URL safe base64 encoding

=head1 SYNOPSIS

  my $string = 'This is a message';
  my $enc = b64url_encode($string);
  $string = b64url_decode($enc);

=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::Base64url> is a plugin for
URL safe Base64 encoding and decoding.

=head FUNCTIONS

=head2 C<b64url_encode>

  print b64url_encode('This is a message');
  print b64url_encode('This is a message', 0);

Encodes a string 64-based with URL safe characters.
A second parameter indicates, if trailing equal signs
are wanted. The default is true.

=head2 C<b64url_decode>

  print b64url_decode('VGhpcyBpcyBhIG1lc3NhZ2U=');

Decodes a 64-based string with URL safe characters.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
