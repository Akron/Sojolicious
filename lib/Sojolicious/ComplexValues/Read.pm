use strict;
use warnings;

# Todo: Allow for multiple filters

# Constants
use constant {
  ID      => 0,
  RES_ID  => 1,
  OBJ_ID  => 2,
  PRI_KEY => 3,
  SEC_KEY => 4,
  VAL     => 5
};

# Read complex value
sub read {
  my ($self, $param, $response) = @_;

  my $oro  = $self->{oro};
  my $name = $self->{name};
  my $dbh  = $oro->{dbh};

  $response //= {};

  my ($id, @resource);
  my ($total_results, $start_index) = (0, 0);

  # Set count to default
  my $count = $self->items_per_page;

  my ($single, $id_request) = (0, 0);

  # Single resource
  if (exists $param->{id} && $param->{id}) {
    $id = delete $param->{id};

    # Split string id array
    if (index($id, ',') > 0) {
      $id = [ split(/,/, $id) ];
    };

    # Single request or id request
    unless (ref($id)) {

      # Multiple id requests
      if ($id eq '---') {
	$id_request = 1;
	$id = undef;
      }

      # Single request
      else {
	$single = 1;

	# Single id request
	if ($id eq '-') {
	  $id_request = 1;
	  $id = undef;
	};
      };
    };
  };

  # Id request
  if (defined $id) {

    my ($sql, $bind_param) = _id_sql($name, {%$param}, $id);

    # warn $sql;

    my $entry_lines =
      $dbh->selectall_arrayref($sql, {}, @$bind_param);

    # Single entry
    if ($single) {
      ($resource[0]) = _lines_to_entries($entry_lines);
      $total_results = 1 if $resource[0];
    }

    # Multiple entries
    else {
      @resource = _lines_to_entries($entry_lines);
      $total_results = scalar(@resource);
    };
  }

  # Multiple resources
  else {

    my ($sql, $bind_param) =
      _multiple_basic_sql($name, $param);

    # warn $sql;

    # Get offset and count
    if ($param->{startIndex} && $param->{startIndex} > 0) {
      $start_index = $param->{startIndex};
    };

    # Get count
    if ($param->{count} && $param->{count} > 0) {
      $count = $param->{count};
      $response->{itemsPerPage} = $count;
    };

    # Prepare and execute
    my ($rv, $sth) = $oro->prep_and_exec($sql, $bind_param, 'cached');;

    # Todo: Check for rv

    # Fetch all matching ids
    my @matches = map($_->[0],  @{$sth->fetchall_arrayref});

    # Set total results
    $total_results = @matches;

    # Splice the result based on the given limitations
    splice(@matches, 0, $start_index) if $start_index != 0;
    if (($count + $start_index) <= $total_results) {
      splice(@matches, $count);
    };

    # Return ids
    if ($id_request && @matches) {
      @resource = @matches;
    }

    # Request entries
    elsif (@matches) {

      ($sql, $bind_param) = _multiple_fetch_sql($name, $param, \@matches);

      # warn $sql;

      # Prepare
      my ($rv, $sth) = $oro->prep_and_exec($sql, $bind_param, 'cached');

      # Todo: Check for rv

      my $entry_lines = $sth->fetchall_arrayref;

      # Lines to entries
      @resource = _lines_to_entries($entry_lines);

      # Sort resources
      if (exists $param->{sortBy}) {
	my %matches;

	my $i = 0;
	$matches{$_} = $i++ foreach @matches;

	my @new_resource;
	foreach my $res (@resource) {
	  $new_resource[ $matches{ $res->{id} } ] = $res;
	};
	@resource = @new_resource;
	@new_resource = ();
      };
    };
  };

  # Other startIndex values currently not supported
  $response->{startIndex} = 0;

  for ($response) {
    $_->{totalResults} = $total_results;
    $_->{startIndex}   = $start_index;

    my $return = $id_request ? 'id' : 'entry';

    # Non-empty response
    if ($resource[0]) {
      $_->{$return} = $single ? $resource[0] : \@resource;
    }

    # Empty response
    elsif ($id_request && !$single) {
      $_->{$return} = [];
    }

    # empty non-id response
    else {
      $_->{$return} = $single ? {} : [];
    };
  };

  # Return response
  return $response;
};


# Build id based resource sql
sub _id_sql {
  my ($name, $param, $id) = @_;

  my @parameter;

  my $sql = 'SELECT * FROM ' . $name . ' WHERE ';

  # Multiple ids
  if (ref($id) && ref($id) eq 'ARRAY') {
    $sql .= 'res_id in (' . _q($id) . ') ';
    push(@parameter, @$id);
  }

  # Single id
  else {
    $sql .= 'res_id = ? ';
    @parameter = ($id);
  };

  # Presentation - fields
  if (exists $param->{fields}) {
    my ($sql_w_fields, $fields) = _sql_fields($name, $param->{fields});
    $sql .= ' AND ' . $sql_w_fields;
    push(@parameter, @$fields);
  };

  # Sort lines
  $sql .= ' ORDER BY res_id, id ASC';

  return ($sql => \@parameter);
};


# Build sql query for multiple resources before further filtering
sub _multiple_basic_sql {
  my ($name, $param) = @_;

  my @tables = ('ShowTable');
  my (@criterion, @parameter);

  # Get date construct
  my $date;
  if (exists $param->{updatedSince}) {
    $date = Mojolicious::Plugin::Date::RFC3339->new(
      delete $param->{updatedSince}
    );
    $date = $date ? $date->epoch : undef;
  };

  # Simple updatedSince access
  if ($date &&
	!exists $param->{sortBy} &&
	  !exists $param->{filterBy}) {

    my $sql = 'SELECT res_id FROM '.$name.'_UPDATED '.
              'WHERE updated > ? ';
    @parameter = ($date);
    return ($sql, \@parameter);
  };

  my $sql_s  = 'SELECT ShowTable.res_id ';
  my $sql_o = '';

  # Use simple filter
  my $filter;
  if (exists $param->{filterBy}) {
    $filter = [
      $param->{filterBy},
      $param->{filterOp},
      $param->{filterValue} // undef
    ];
  };

  # Simple access
  if ($filter &&
	!exists $param->{sortBy}) {
    my ($parameter, $criterion) = _sql_filter('ShowTable', $filter);
    push(@parameter, @$parameter);
    push(@criterion, @$criterion);
  }

  # Complicate access
  else {

    # Filter
    my $table = 1;
    if ($filter) {
      my ($parameter, $criterion) = _sql_filter('Table' . $table, $filter);
      push(@parameter, @$parameter);
      push(@criterion, @$criterion);
      unshift(@tables, 'Table' . $table++);
    };

    # Sorted
    if (exists $param->{sortBy}) {

      # TODO: Plural values become singular values: emails -> email
      # TODO: support primary => true for sorting of plural complex values
      # TODO: Use _sql_filter here
      my ($sort_pri_key, $sort_sec_key) = split(/\./, $param->{sortBy});

      if ($sort_sec_key) {
	push(@parameter, $sort_sec_key);
	push(@criterion, 'OrderTable.sec_key = ?');
      };

      push(@parameter, $sort_pri_key);
      push(@criterion, 'OrderTable.pri_key = ?');

      push(@tables, 'OrderTable');

      $sql_o = ' ORDER BY OrderTable.val ';

      # SortOrder
      # descending
      if (exists $param->{sortOrder} &&
	    lc($param->{sortOrder}) eq 'descending') {
	$sql_o .= 'DESC '
      }

      # default - Ascending
      else {
	$sql_o .= 'ASC '
      };
    };
  };

  # updatedSince
  # For SQL optimization this is the latest criterion
  if ($date) {
    unshift(@criterion, 'ShowTable.res_id = UpdatedTable.res_id');
    push(@criterion,    'UpdatedTable.updated > ?');
    push(@parameter,    $date);
    unshift(@tables,    $name . '_UPDATED AS UpdatedTable');
  };

  # Ignore deleted entries
  push(@criterion, 'ShowTable.pri_key NOT NULL');

  # Add all tables that have no alias
  my $sql_f  = ' FROM '.
    join(',',
	 map(
	   index(lc($_),' as ') >= 0 ? $_ : $name.' AS '.$_,
	   @tables
	 )
       ).' ';

  # Add res_id constraint
  foreach (@tables) {
    next if $_ eq 'ShowTable';

    # Don't constrain blindly with otherwise connected tables
    if (index(lc($_), ' as ') == -1 ) {
      push(@criterion, 'ShowTable.res_id = ' . $_ .'.res_id');
    };
  };

  # sql where clause
  my $sql_w  = '';
  if ($criterion[0]) {
    $sql_w .= ' WHERE '. join(' AND ', @criterion);
  };

  # sql group by clause for distinct res_ids
  my $sql_g  = ' GROUP BY ShowTable.res_id ';

  # Get all values
  my $sql = $sql_s . $sql_f . $sql_w . $sql_g . $sql_o;

  # Return sql statement and parameter
  return ($sql, \@parameter);
};


# Build sql query for fetching multiple resources
sub _multiple_fetch_sql {
  my ($name, $param, $matches) = @_;

  my $sql = 'SELECT * FROM ' . $name . ' ';

  $sql .= ' WHERE res_id IN (' . _q($matches) . ') ';
  my @parameter = @$matches;

  # Presentation - fields
  if (exists $param->{fields}) {
    my ($sql_w_fields, $fields) = _sql_fields($name, $param->{fields});
    $sql .= ' AND ' . $sql_w_fields;
    push(@parameter, @$fields);
  };

  # Sort lines based on res_id and ids
  $sql .= ' ORDER BY res_id, id';
  return ($sql => \@parameter);
};


# Build sql fields
sub _sql_fields {
  my ($name, $fields) = @_;
  my @fields;

  # Fields is an array ref
  if (ref($fields) && ref($fields) eq 'ARRAY') {
    return ('',()) if $fields ~~ '@all';
    @fields = @$fields;
  }

  # Fields is a string
  else {
    return ('',()) if $fields eq '@all';
    my %fields = map { $_ => 1 } split(/\s*,\s*/, $fields.',id');
    @fields = keys %fields;
  };

  # No fields specified
  return ('',()) unless @fields;

  # Create sql string
  my $sql = $name . '.pri_key IN (' . _q( \@fields ) . ') ';

  # Return sql query and field array
  return ($sql, \@fields);
};


# Build sql filter
sub _sql_filter {
  my $name = shift;
  my $filter = shift;

  my (@parameter, @criterion);

  my ($by, $op, $value) = @$filter;

  # TODO: Plural values become singular values: emails -> email
  my ($filter_pri_key, $filter_sec_key) = split(/\./, $by);

  if ($filter_sec_key) {
    push(@parameter, $filter_sec_key);
    push(@criterion, $name . '.sec_key = ?');
  };

  push(@parameter, $filter_pri_key);
  push(@criterion, $name . '.pri_key = ?');


  # Equals, contains, startswith
  if ($op =~ /^(?:equals|contains|startswith)$/oi) {
    if (defined $value) {

      # Equals
      if ($op eq 'equals') {
	unshift(@criterion, $name . '.val = ?');
	unshift(@parameter, $value);
      }

      # Contains and startswith
      else {
	unshift(@criterion, $name . '.val LIKE ?');

	# Contains
	if ($op eq 'contains') {
	  unshift(@parameter, '%' . $value . '%');
	}

	# Startswith
	else {
	  unshift(@parameter, $value . '%');
	};
      };
    }

    # No filterValue specified
    else {
      # error
      return ([], []);
    };
  }

  # Present
  elsif ($op eq 'present') {
    push(@criterion, $name . '.val NOT NULL');
    push(@parameter, $by);
  }

  # Unknown operation
  else {
    # error
    return ([], []);
  };

  return (\@parameter, \@criterion);
};


# Lines to entries
sub _lines_to_entries ($) {
  my $lines = shift;

  my ($line_c, $res_id) = (0, 0);
  my (@res, %res, %res_plural);
  my ($val, $key, $vkey);

  my $_new_res = sub () {

    # add pural values
    foreach $vkey (sort keys %res_plural) {
      $val = $res_plural{$vkey};
      $key = delete $val->{'-key'};
      $res{$key} //= [];
      push (@{ $res{$key} }, $val);
    };

    push(@res, { %res }) if exists $res{id};

    (%res, %res_plural) = ();
  };

  # Loop through all lines
  my $line;
  while ($line = $lines->[$line_c++]) {

    # New res_id
    unless ($res_id) {
      $res_id = $line->[RES_ID]
    }

    elsif ($line->[RES_ID] != $res_id) {
      $_new_res->();
      $res_id = $line->[RES_ID];
    };

    if ($line->[PRI_KEY] && defined $line->[VAL]) {

      # plural objects (Hashes)
      # accounts =>
      # [{ domain => ..., username => ...}]
      if ($line->[OBJ_ID]) {
	( $res_plural{$line->[OBJ_ID]} //= {} )->{$line->[SEC_KEY]} =
	  $line->[VAL];
      }

      # Simple value
      # note => 'Note'
      elsif (!$line->[SEC_KEY]) {
	$res{$line->[PRI_KEY]} = $line->[VAL];
      }

      # Plural objects (Array)
      # tags => ['cool','nice']
      elsif ($line->[SEC_KEY] eq '%') {
	$res{$line->[PRI_KEY]} //= [];
	push(@{$res{$line->[PRI_KEY]}}, $line->[VAL]);
      }

      # Complex value
      # name => { familyName => ..., givenName => ... }
      else {
	($res{$line->[PRI_KEY]} //= {})->{$line->[SEC_KEY]} =
	  $line->[VAL];
      };
    }

    # Init for plural objects
    elsif ($line->[PRI_KEY]) {
      ($res_plural{$line->[ID]} //= {})->{'-key'} =
	$line->[PRI_KEY];
    };
  };

  $_new_res->();

  return @res;
};

# questionmark string
sub _q ($) {
  join(',', split('', '?' x scalar(@{$_[0]})));
};

1;

__END__

# For documentation, see Sojolicious::ComplexValues.
