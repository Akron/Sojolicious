package Mojolicious::Plugin::Util::ArbitraryBase;
use Mojo::Base 'Mojolicious::Plugin';

# Implement with GMP or PARI if existent
use Math::BigInt try => 'GMP,Pari';

my %bases;

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Util')) {
    if ($config_param = $config_param->{ArbitraryBase}) {
      $param = { %$config_param, %$param };
    };
  };

  # Register all encoding schemes
  while (my ($name, $array) = each %$param) {

    # Get character array
    my @array = split('', ref($array) ? join('',@$array) : $array );

    # Get and calculate base array
    my $num = 0;
    my (%base, @base);
    foreach (@array) {

      # Do not allow double characters
      next if exists $base{$_};

      # Set character value
      $base{$_} = $num++;

      # Push to base array
      push(@base, $_);
    };

    # Regular Expression from base array
    my $re = '[^' . join('', map(quotemeta, @base)) . ']';

    # Save base encoding scheme globally
    $bases{$name} = \%base;

    # Based on Math::BaseCnv by Pip Stuart <Pip@CPAN.Org>
    # Create subroutine for encoding
    my $encode = '
sub {
  my $n = $_[1];
  return undef if $n =~ /\D/ || $n < 0;

  my @b_array = qw/'.join(' ', @base).'/;
  my $b_num = ' . $num . ';

  $n = Math::BigInt->new($n);
  my $t = "";
  while ($n) {
    $t = $b_array[$n % $b_num] . $t;
    $n = int($n / $b_num);
  };
  return $t || 0;
}';

    # Create subroutine for decoding
    my $decode = '
sub {
  my $t = $_[1];
  return if (!defined $t || $t =~ /' . $re . '/);
  my %b_bases = %{$bases{"' . $name . '"}};
  my $n = Math::BigInt->new();
  while (length($t)) {
    $n->badd($b_bases{substr($t, 0, 1, "")});
    $n->bmul(' . $num . ');
  };
  return int($n->bdiv('.$num.'));;
}';


    my $encode_ref = eval $encode;
    die $@ . ':' . $! if $@;

    my $decode_ref = eval $decode;
    die $@ . ':' . $! if $@;


    # Establish encoding helper
    $mojo->helper(
      $name . '_encode' => $encode_ref
    );

    # Establish decoding helper
    $mojo->helper(
      $name . '_decode' => $decode_ref
    );
  };
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Util::ArbitraryBase - Arbitrary base encoding

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('Util::ArbitraryBase' => {
    base26 => '2345679bdfhmnprtFGHJLMNPRT'
  });

  # In Controllers
  my $encode = $c->base26_encode(402758585289);
  print $c->base26($encode);

  # Mojolicious::Lite
  plugin 'Util::ArbitraryBase' => {
    base26 => '2345679bdfhmnprtFGHJLMNPRT'
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::ArbitraryBase> is a plugin for
encoding and decoding from integer values to arbitrary character bases.

=head1 METHODS

=head2 C<register>

  # Mojolicious
  $app->plugin('Util::ArbitraryBase' => {
    base26 => '2345679bdfhmnprtFGHJLMNPRT'
  });

  # Mojolicious::Lite
  plugin 'Util::ArbitraryBase' => {
    base26 => '2345679bdfhmnprtFGHJLMNPRT'
  };

Called when registering the plugin.
Various encodings can
be defined in a hash reference, where a name of the scheme
is followed by the ordered character set allowed for the
encoding. Double characters are ignored.
All parameters can be set either on registration or
as part of the configuration file with the key C<ArbitraryBase>
under the Key C<Util>.


=head1 HELPERS

=head2 C<*_encode>

  plugin 'Util::ArbitraryBase' => {
    base5  => 'aeiou',
    foobar => 'qwerty'
  };

  $c->base5_encode(465578);   # eauouuoao
  $c->foobar_encode(465578);  # wryywete

Returns a string based on the given encoding.
The string will have no trailing empty characters.

When registering the plugin, various encodings can
be defined in a hash reference, where a name of the scheme
is followed by the ordered character set allowed for the
encoding. Double characters are ignored.

=head2 C<*_decode>

  plugin 'Util::ArbitraryBase' => {
    base5  => 'aeiou',
    foobar => 'qwerty'
  };

  $c->base5_encode('eauouuoao'); # 465578
  $c->foobar_encode('wryywete'); # 465578

Returns an integer based on the given encoding.
The name of the helper is established when
registering the plugin.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
