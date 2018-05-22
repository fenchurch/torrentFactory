#!/bin/bash
server=plex.service
port=32400
sectionsURL="http://$server:$port/library/sections"
token=psBHr4cXsCpQfUrCrGqk
tokenHeader="X-Plex-Token:$token"

section=${1:-TV\ Shows}
xpath=/usr/bin/xpath
[[ "$(uname)" == "Linux" ]] && xpath="$xpath -q -e" || :

sectionID=$(curl -sH "$tokenHeader" "$sectionsURL" | $xpath "string(//Directory[@title='$section']/@key)" 2>&0)
echo $sectionsURL - $sectionID

curl -sH -"$tokenHeader" "$sectionsURL/$sectionID/refresh?X-Plex-Token=$token"
