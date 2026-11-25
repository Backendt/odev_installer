# Installer for Odev and AI:

1. Check that you are in the Odoo organization

If you can open https://github.com/odoo/enterprise/ (non 404 error) then you don't need to do anything, you can proceed to step 2.

If you have a 404 error ("Not Found"), you need to [ask your beloved sysadmins](mailto:it@odoo.com) to add your github account to Odoo organization (create a github account if you don't have any).
Make sure to give your Github username to sysadmins while requesting for access.

Then you will get an invitation email. Click and accept invitation. 

2. Open a new terminal (Ctrl+Alt+T)

```sh
cd ~ && wget -O install.sh https://raw.githubusercontent.com/Backendt/odev_installer/refs/heads/main/install.sh
bash install.sh
```
> "Your password" and "session password" is the password you type when you open your laptop and login.

> When it asks for `passphrase`, just press Enter twice.

```sh
odev create test
```

----

Slides FR:
https://docs.google.com/presentation/d/1iG4JZrqhFBeFkSnpatAwDD6jGy5yc4ru

Slides EN:
https://docs.google.com/presentation/d/1FOAsVbcpekgvn1lmKihxhxxdeCug3rzz
