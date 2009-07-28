package DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::Sybase::Base
  DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server
  DBIx::Class::Storage::DBI::NoBindVars
/;
use mro 'c3';

sub _rebless {
  my $self = shift;
  $self->disable_sth_caching(1);

# LongReadLen doesn't work with MSSQL through DBD::Sybase, and the default is
# huge on some versions of SQL server and can cause memory problems, so we
# fix it up here.
  $self->set_textsize(
    eval { $self->_dbi_connect_info->[-1]->{LongReadLen} } ||
    32768 # the DBD::Sybase default
  );
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server - Storage::DBI subclass for MSSQL via
DBD::Sybase

=head1 SYNOPSIS

This subclass supports MSSQL server connections via L<DBD::Sybase>.

=head1 CAVEATS

This storage driver uses L<DBIx::Class::Storage::DBI::NoBindVars> as a base.
This means that bind variables will be interpolated (properly quoted of course)
into the SQL query itself, without using bind placeholders.

More importantly this means that caching of prepared statements is explicitly
disabled, as the interpolation renders it useless.

The actual driver code for MSSQL is in
L<DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server>.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
