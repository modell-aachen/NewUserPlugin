# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2014-2016 Modell Aachen GmbH http://www.modell-aachen.de
# Copyright (C) 2006-2013 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

###############################################################################
package Foswiki::Plugins::NewUserPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Error qw(:try);

our $VERSION = '2.41';
our $RELEASE = "2";
our $SHORTDESCRIPTION = 'Create a user topic if it does not exist yet';
our $NO_PREFS_IN_TOPIC = 1;
our $done;

###############################################################################
sub initPlugin {
  Foswiki::Func::registerRESTHandler('createUserTopics', \&restCreateUserTopics, authenticate => 1, validate => 0, http_allow => 'GET,POST');

  $done = 0;
  return 1;
}

###############################################################################
sub _writeDebug {
  if ($Foswiki::cfg{NewUserPlugin}{Debug}) {
      Foswiki::Func::writeDebug("NewUserPlugin.pm: " . $_[0]);
  }
}

###############################################################################
sub restCreateUserTopics {
  my $session = shift;

  my $mapping = $session->{users}{mapping};
  my $passwordManager = $mapping->{passwords};

  if ($passwordManager->canFetchUsers) {
    my $usersWeb = $Foswiki::cfg{UsersWebName};
    my $it = $passwordManager->fetchUsers();
    my $count = 0;
    while ($it->hasNext()) {
      my $loginName = $it->next();
      my $wikiName = Foswiki::Func::userToWikiName($loginName, 1);
      _writeDebug("Check loginName=$loginName, wikiName=$wikiName");
      next if Foswiki::Func::topicExists($usersWeb, $wikiName);
      _writeDebug("Create a user topic for $wikiName");
      createUserTopic($wikiName);
      $count++;
    }

    _writeDebug("Created $count user topics");
  } else {
    Foswiki::Func::writeWarning("Can't fetch users");
  }

  return;
}

###############################################################################
# unfortunately we can't use the initializeUserHandler as the engine is not
# fully initialized then. even the beforeCommonTagsHandler get's called in
# a half-init state in the middle of the main constructor. so we have to wait for
# the main object to be fully initialized, i.e. its i18n subsystem
sub beforeCommonTagsHandler {
  return if !defined($Foswiki::Plugins::SESSION->{i18n}) || $done;
  $done = 1;

  _writeDebug("Called beforeCommonTagsHandler");

  my $wikiName = Foswiki::Func::getWikiName();
  my $usersWeb = $Foswiki::cfg{UsersWebname};
  return if Foswiki::Func::topicExists($usersWeb, $wikiName);

  _writeDebug("Create homepage for user $wikiName");
  createUserTopic($wikiName)
}

###############################################################################
sub expandVariables {
  my ($text, $topic, $web) = @_;

  return '' unless $text;

  $text =~ s/^\"(.*)\"$/$1/go;

  my $found = 0;
  my $mixedAlphaNum = $Foswiki::regex{'mixedAlphaNum'};

  $found = 1 if $text =~ s/\$perce?nt/\%/go;
  $found = 1 if $text =~ s/\$nop//go;
  $found = 1 if $text =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/go;
  $found = 1 if $text =~ s/\$dollar/\$/go;

  $text = Foswiki::Func::expandCommonVariables($text, $topic, $web) if $found;

  return $text;
}

###############################################################################
# Creates a user topic for the given wikiName
sub createUserTopic {
  my $wikiName = shift;

  my $systemWeb = $Foswiki::cfg{SystemWebName};
  my $usersWeb = $Foswiki::cfg{UsersWebName};
  my $newUserTemplate =
    $Foswiki::cfg{NewUserPlugin}{NewUserTemplate} ||
    Foswiki::Func::getPreferencesValue('NEWUSERTEMPLATE') || 'NewUserTemplate';
  my $tmplTopic;
  my $tmplWeb;
  my $wikiUserName = $usersWeb.'.'.$wikiName;

  # Search the NEWUSERTEMPLATE
  $newUserTemplate =~ s/^\s+//go;
  $newUserTemplate =~ s/\s+$//go;
  $newUserTemplate =~ s/\%SYSTEMWEB\%/$systemWeb/g;
  $newUserTemplate =~ s/\%MAINWEB\%/$usersWeb/g;

  # In users web
  ($tmplWeb, $tmplTopic) = Foswiki::Func::normalizeWebTopicName($usersWeb, $newUserTemplate);

  unless (Foswiki::Func::topicExists($tmplWeb, $tmplTopic)) {

    ($tmplWeb, $tmplTopic) = Foswiki::Func::normalizeWebTopicName($systemWeb, $newUserTemplate);

    unless (Foswiki::Func::topicExists($tmplWeb, $tmplTopic)) {
      writeWarning("no new user template found"); # not found
      return;
    }
  }

  _writeDebug("newusertemplate = $tmplWeb.$tmplTopic");

  # Read the template
  my ($meta, $text) = Foswiki::Func::readTopic($tmplWeb, $tmplTopic);
  unless ($meta) {
    writeWarning("can't read $tmplWeb.$tmplTopic");
    return;
  }

  # Insert data
  my $loginName = Foswiki::Func::wikiToUserName($wikiName);
  $text =~ s/\$nop//go;
  $text =~ s/\%USERNAME\%/$loginName/go;
  $text =~ s/\%WIKINAME\%/$wikiName/go;
  $text =~ s/\%WIKIUSERNAME\%/$wikiUserName/go;
  $text =~ s/\%EXPAND\{(.*?)\}\%/expandVariables($1, $wikiName, $usersWeb)/ge;
  $text =~ s/\%STARTEXPAND\%(.*?)\%STOPEXPAND\%/Foswiki::Func::expandCommonVariables($1, $wikiName, $usersWeb)/ges;

  foreach my $field ($meta->find('FIELD'), $meta->find('PREFERENCE')) {
    $field->{value} =~ s/\%USERNAME\%/$loginName/go;
    $field->{value} =~ s/\%WIKINAME\%/$wikiName/go;
    $field->{value} =~ s/\%WIKIUSERNAME\%/$wikiUserName/go;
    $field->{value} =~ s/\%EXPAND\{(.*?)\}\%/expandVariables($1, $wikiName, $usersWeb)/ge;
    $field->{value} =~ s/\%STARTEXPAND\%(.*?)\%STOPEXPAND\%/Foswiki::Func::expandCommonVariables($1, $wikiName, $usersWeb)/ges;
  }

  _writeDebug("Patch in RegistrationAgent");

  my $session = $Foswiki::Plugins::SESSION;
  my $origCUID = $session->{user};
  my $registrationAgentCUID = Foswiki::Func::getCanonicalUserID($Foswiki::cfg{Register}{RegistrationAgentWikiName});
  _writeDebug("registrationAgentCUID=$registrationAgentCUID");

  $session->{user} = $registrationAgentCUID;
  _writeDebug("Save new user topic $usersWeb.$wikiName");

  try {
    # We use saveAs here in order to prevent other plugins from interfering via handlers, e.g. KVPPlugin.
    my ($newmeta, undef) = Foswiki::Func::readTopic($usersWeb, $wikiName);
    $newmeta->text($text);
    $newmeta->saveAs($usersWeb, $wikiName, nohandlers => 1);
  } catch Error::Simple with {
    writeWarning("Error during save of $usersWeb.$wikiName: " . shift);
  };

  $session->{user} = $origCUID;
}

# MaintenancePlugin integration.
sub maintenanceHandler {
    Foswiki::Plugins::MaintenancePlugin::registerCheck("NewUserPlugin:debugmode", {
        name => "NewUserPlugin debug mode",
        description => "NewUserPlugin debug mode is disabled.",
        check => sub {
            my $result = { result => 0 };
            if ( ( exists $Foswiki::cfg{NewUserPlugin}{Debug} ) and ( $Foswiki::cfg{NewUserPlugin}{Debug} ) ) {
                $result->{result} = 1;
                $result->{priority} = $Foswiki::Plugins::MaintenancePlugin::ERROR;
                $result->{solution} = "Disable {NewUserPlugin}{Debug}.";
            }
            return $result;
        }
    });
}

1;
