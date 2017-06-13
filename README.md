# AdBlock

AdBlock is a minimalist router-based ad blocking script for routers with very limited RAM. It uses the DNS poisoning technique combined with publically available blocklists to re-route all blacklisted domains to a pixelserv client (a tiny one-pixel transparent gif webserver) running on your router. This script, pixelserv, plus the two block lists that it downloads requires a total of about 600 KB.

Your router will need a JFFS partition, SSH access and the ability to set cron jobs, so you will most likely need an aftermarket router firmware such as DD-WRT or Tomato.


### Installation

<ol>
  <li>Create a JFFS partition via your router's admin interface.</li>
  <li>Clone this repo. <pre>cd && mkdir adblock && git clone https://github.com/kidquick/AdBlock adblock</pre></li>
  <li>Grant execute rights to the script. <pre>chmod +x ~/adblock/adblock.sh</pre></li>
  <li>SSH all files to your JFFS partition. <pre>scp ~/adblock/* admin@router:/jffs/dns</pre></li>
  <li>Add the script to router's startup commands (via the router admin GUI).</li>
  <li>Reboot the router.</li>
  <li>Done!</li>
</ol>


### Updating

Blocklists are automatically updated every Monday at 4am. To force an update, run the script with a -f switch. <pre>./adblock.sh -f</pre>
