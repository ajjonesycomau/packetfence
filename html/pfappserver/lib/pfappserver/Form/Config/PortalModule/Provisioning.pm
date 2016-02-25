package pfappserver::Form::Config::PortalModule::Provisioning;

=head1 NAME

pfappserver::Form::Config::PortalModule:Choice

=head1 DESCRIPTION

Form definition to create or update a choice portal module.

=cut

use HTML::FormHandler::Moose;
extends 'pfappserver::Form::Config::PortalModule';
with 'pfappserver::Base::Form::Role::Help';

use captiveportal::DynamicRouting::Module::Provisioning;
sub for_module {'captiveportal::DynamicRouting::Module::Provisioning'}
## Definition

has_field 'skipable' =>
  (
   type => 'Toggle',
   label => 'Skipable',
   unchecked_value => 'disabled',
   checkbox_value => 'enabled',
   default => for_module->meta->get_attribute('skipable')->default->(),
   tags => { after_element => \&help,
             help => 'Whether or not, the provisioning can be skipped' },
  );

sub child_definition {
    return qw(skipable);
}

=over

=back

=head1 COPYRIGHT

Copyright (C) 2005-2016 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

__PACKAGE__->meta->make_immutable;
1;

