package Mojolicious::Plugin::TagHelpers::Pagination;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use POSIX 'ceil';

our @value_list = qw/prev next
		     current_start current_end
		     page_start page_end
		     separator ellipsis/;

# Todo: See HTML::Breadcrumbs for style.
# Todo: Create "format" string for links.
#       Default "<a href="{url}">{label}</a>
# Todo: Make gen on start.

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  foreach (@value_list) {
    $plugin->{$_} = $param->{$_} if defined $param->{$_};
  };

  # Set 'current_start' and 'current_end' symbols,
  # if 'current' template is available.
  # Same for 'page'.
  foreach (qw/page current/) {
    if (defined $param->{$_}) {
      @{$plugin}{$_ . '_start', $_ . '_end'} = split("{$_}", $param->{$_});
      $plugin->{$_ . '_end'} ||= '';
    };
  };

  # Default current start and current end symbols
  for ($plugin) {
    $_->{current_start} //= '[';
    $_->{current_end}   //= ']';
    $_->{page_start}    //= '';
    $_->{page_end}      //= '';
    $_->{prev}          //= '&lt;';
    $_->{next}          //= '&gt;';
    $_->{separator}     //= '&nbsp;';
    $_->{ellipsis}      //= '...';
  };

  # Establish pagination helper
  $mojo->helper(
    pagination => sub {
      shift; # Controller
      return b( $plugin->pagination( @_ ) );
    });
};


# Pagination helper
sub pagination {
  my $self = shift;

  # $_[0] = current page
  # $_[1] = page count
  # $_[2] = template or Mojo::URL

  return '' unless $_[0] || $_[1];

  # No valid count given
  local $_[1] = !$_[1] ? 1 : ceil($_[1]);

  # Template
  my $t = $_[2];
  if (ref $t && ref $t eq 'Mojo::URL') {
    $t = $t->to_abs->to_string;
    $t =~ s/\%7[bB]page\%7[dD]/{page}/g;
  };

  # New parameter hash
  my %values =
    map { $_ => $self->{$_} } @value_list;

  # Overwrite plugin defaults
  if ($_[3] && ref $_[3] eq 'HASH') {
    my $overwrite = $_[3];
    foreach (@value_list) {
      $values{$_}  = $overwrite->{$_} if defined $overwrite->{$_};
    };

    foreach (qw/page current/) {
      if (defined $overwrite->{$_}) {
	@values{$_ . '_start', $_ . '_end'} = split("{$_}", $overwrite->{$_});
	$values{$_ . '_end'} ||= '';
      };
    };
  };

  # Establish string variables
  my ($p, $n, $cs, $ce, $ps, $pe, $s, $el) = @values{@value_list};
  # prev next current_start current_end page_start page_end separator ellipsis

  my $sub = sublink_gen($t,$ps,$pe);

  # Pagination string
  my $e;
  my $counter = 1;

  if ($_[1] >= 7){

    # < [1] #2 #3
    if ($_[0] == 1){
      $e .= $p . $s .
	    $cs . '1' . $ce . $s .
	    $sub->('2') . $s .
	    $sub->('3') . $s;
    }

    # < #1 #2 #3
    elsif (!$_[0]) {
      $e .= $p . $s;
      $e .= $sub->($_) . $s foreach (1 .. 3);
    }

    # #< #1
    else {
      $e .= $sub->(($_[0] - 1), $p) . $s .
            $sub->('1') . $s;
    };

    # [2] #3
    if ($_[0] == 2){
      $e .= $cs . '2' . $ce . $s .
	    $sub->('3') . $s;
    }

    # ...
    elsif ($_[0] > 3){
      $e .= $el . $s;
    };

    # #x-1 [x] #x+1
    if (($_[0] >= 3) && ($_[0] <= ($_[1] - 2))){
      $e .= $sub->($_[0] - 1) . $s .
	    $cs . $_[0] . $ce . $s .
	    $sub->($_[0] + 1) . $s;
    };

    # ...
    if ($_[0] < ($_[1] - 2)){
      $e .= $el . $s;
    };

    # number is prefinal
    if ($_[0] == ($_[1] - 1)){
      $e .= $sub->($_[1] - 2) . $s .
	    $cs . $_[0] . $ce . $s;
    };

    # Number is final
    if ($_[0] == $_[1]){
      $e .= $sub->($_[1] - 1) . $s .
            $cs . $_[1] . $ce . $s . $n;
    }

    # Number is anywhere in between
    else {
      $e .= $sub->($_[1]) . $s .
            $sub->(($_[0] + 1), $n);
    };
  }

  # Counter < 7
  else {

    # Previous
    if ($_[0] > 1){
      $e .= $sub->(($_[0] - 1), $p) . $s;
    } else {
      $e .= $p . $s;
    };

    # All numbers in between
    while ($counter <= $_[1]){
      if ($_[0] != $counter) {
        $e .= $sub->($counter) . $s;
      }

      # Current
      else {
        $e .= $cs . $counter . $ce . $s;
      };

      $counter++;
    };

    # Next
    if ($_[0] != $_[1]){
      $e .= $sub->(($_[0] + 1), $n);
    } else {
      $e .= $n;
    };
  };

  # Pagination string
  $e;
};

# Sublink function generator
sub sublink_gen {
  my ($url, $ps, $pe) = @_;

  my $s = 'sub {';
  # $_[0] = number
  # $_[1] = number_shown

  # Url is template
  if ($url) {
    $s .= 'my $url=' . b($url)->quote . ';';
    $s .= '$url =~ s/\{page\}/$_[0]/g;';
  }

  # No template given
  else {
    $s .= 'my $url = $_[0];';
  };

  $s .= 'my $n = $_[1] || ' .
    b($ps)->quote . ' . $_[0] . ' . b($pe)->quote . ';';

  # Create sublink
  $s .= q{return '<a href="' . $url . '">' . $n . '</a>';};
  $s .= '}';

  my $x = eval($s);

  if ($@) {
    warn $@;
  };

  return $x;
};


1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::TagHelpers::Pagination

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('TagHelpers::Pagination' => {
    separator => ' ',
    current => '<strong>{current}</strong>'
  });

  # Mojolicious::Lite
  plugin 'TagHelpers::Pagination',
    separator => ' ',
    current   =>  '<strong>{current}</strong>';

  # In Templates
  <%= pagination(4, 6) %>

=head1 DESCRIPTION

L<Mojolicious::Plugin::TagHelpers::Pagination> helps to create
pagination elements on websites.

=head1 PARAMETERS

For the layout of the pagination string, the plugin accepts the
following parameters, that are able to overwrite the default
layout elements. These parameters can again be overwritten in
the pagination helper.

=over 2

=item C<prev>

Symbol for previous pages. Defaults to C<&lt;>.

=item C<next>

Symbol for next pages. Defaults to C<&gt;>.

=item C<ellipsis>

Placeholder symbol for hidden pages. Defaults to C<...>.

=item C<current>

Pattern for current page number. The C<{current}> is a
placeholder for the current number.
Defaults to C<[{current}]>.
Instead of a pattern, both sides of the current number
can be defined with C<current_start> and C<current_end>.

=item C<pge>

Pattern for page number. The C<{page}> is a
placeholder for the page number.
Defaults to C<{page}>.
Instead of a pattern, both sides of the page number
can be defined with C<page_start> and C<page_end>.

=item C<separator>

Symbol for the separation of pagination elements.
Defaults to C<&nbsp;>.

=back

=head1 HELPERS

=head2 C<pagination>

  # In Templates:
  %= pagination(4, 6 => '/page-{page}.html');
  % my $url = Mojo::URL->new->query({ page => '{page}'});
  %= pagination(4, 6 => $url);
  %= pagination(4, 6 => '/page/{page}.html', { current => '<b>{current}</b>' }

Generates a pagination string.
Expects at least two numeric values, the current page number and
the total count of pages.
Additionally it accepts a link pattern and a hash reference
with parameters overwriting the default plugin parameters for
pagination.
The link pattern can be a string using the placeholder C<{page}>
for the page number it should link to. It's also possible to give a
L<Mojo::URL> object containing the placeholder.
The placeholder can be used multiple times.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
