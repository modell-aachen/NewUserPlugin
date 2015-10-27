# ---+ Extensions
# ---++ NewUserPlugin
# This is the configuration used by the <b>NewUserPlugin</b>.

# **STRING**
# Template topic to be used when creating a new user page in "Web.Topic" format.
$Foswiki::cfg{NewUserPlugin}{NewUserTemplate} = '%SYSTEMWEB%.NewLdapUserTemplate';

# **BOOLEAN**
# Enable/disable output to debug.log.
$Foswiki::cfg{NewUserPlugin}{Debug} = 0;
