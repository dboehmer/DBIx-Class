package DBIx::Class::Storage::DBI::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::AmbiguousGlob DBIx::Class::Storage::DBI/;
use mro 'c3';

use List::Util();

__PACKAGE__->sql_maker_class('DBIx::Class::SQLAHacks::MSSQL');

sub insert_bulk {
  my $self = shift;
  my ($source, $cols, $data) = @_;

  my $identity_insert = 0;

  COLUMNS:
  foreach my $col (@{$cols}) {
    if ($source->column_info($col)->{is_auto_increment}) {
      $identity_insert = 1;
      last COLUMNS;
    }
  }

  if ($identity_insert) {
    my $table = $source->from;
    $self->dbh->do("SET IDENTITY_INSERT $table ON");
  }

  $self->next::method(@_);

  if ($identity_insert) {
    my $table = $source->from;
    $self->dbh->do("SET IDENTITY_INSERT $table OFF");
  }
}

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

# cast MONEY values properly
  if ($op eq 'insert' || $op eq 'update') {
    my $fields = $args->[0];
    my $col_info = $self->_resolve_column_info($ident, [keys %$fields]);

    for my $col (keys %$fields) {
      if ($col_info->{$col}{data_type} =~ /^money\z/i) {
        my $val = $fields->{$col};
        $fields->{$col} = \['CAST(? AS MONEY)', [ $col => $val ]];
      }
    }
  }

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    $sql .= ';SELECT SCOPE_IDENTITY()';

    my $col_info = $self->_resolve_column_info($ident, [map $_->[0], @{$bind}]);
    if (List::Util::first { $_->{is_auto_increment} } (values %$col_info) ) {

      my $table = $ident->from;
      my $identity_insert_on = "SET IDENTITY_INSERT $table ON";
      my $identity_insert_off = "SET IDENTITY_INSERT $table OFF";
      $sql = "$identity_insert_on; $sql; $identity_insert_off";
    }
  }

  return ($sql, $bind);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);
  if ($op eq 'insert') {
    $self->{_scope_identity} = $sth->fetchrow_array;
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}


sub last_insert_id { shift->{_scope_identity} }

sub build_datetime_parser {
  my $self = shift;
  my $type = "DateTime::Format::Strptime";
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type->new( pattern => '%Y-%m-%d %H:%M:%S' );  # %F %T
}

sub sqlt_type { 'SQLServer' }

sub _sql_maker_opts {
  my ( $self, $opts ) = @_;

  if ( $opts ) {
    $self->{_sql_maker_opts} = { %$opts };
  }

  return { limit_dialect => 'Top', %{$self->{_sql_maker_opts}||{}} };
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::MSSQL - Base Class for Microsoft SQL Server support
in DBIx::Class

=head1 SYNOPSIS

This is the base class for Microsoft SQL Server support, used by
L<DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server> and
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>.

=head1 IMPLEMENTATION NOTES

Microsoft SQL Server supports three methods of retrieving the IDENTITY
value for inserted row: IDENT_CURRENT, @@IDENTITY, and SCOPE_IDENTITY().
SCOPE_IDENTITY is used here because it is the safest.  However, it must
be called is the same execute statement, not just the same connection.

So, this implementation appends a SELECT SCOPE_IDENTITY() statement
onto each INSERT to accommodate that requirement.

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
