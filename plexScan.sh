#!/bin/bash
__scriptVersion=1.
__scriptPID=$$
__scriptPath="$(cd "$(dirname "$0")"; pwd -P )"
__scriptFile="$(basename "$0")"

# Function ===================================================================== 
#           Name:  plexScan.sh
#         Author:  Rusty Gibbs 
#       Homepage:  http://www.wickedidol.com
#            Git:  https://github.com/fenchurch/torrentFactory.git
#        Created:  2018-05-05
#       Modified:  2018-08-02
# ==============================================================================
usage="usage:
$__scriptFile -s|--section TV Show|Movie {server}"
# user vars =============================================================={{{
server=plex.service
port=32400
token=psBHr4cXsCpQfUrCrGqk
xpath=/usr/bin/xpath
# ===========================================================================}}}

sectionsURL="http://$server:$port/library/sections"
tokenHeader="X-Plex-Token:$token"
[[ "$(uname)" == "Linux" ]] && xpath="$xpath -q -e" || :

main(){
    section=${section:-TV\ Shows}
    sectionID=$(curl -sH "$tokenHeader" "$sectionsURL" |\
        $xpath "string(//Directory[@title='$section']/@key)"\
        2>&0)
    echo $sectionsURL - $sectionID    
    curl -sH -"$tokenHeader"\
        "$sectionsURL/$sectionID/refresh?X-Plex-Token=$token"
}
while true; do
    case "$1" in
    --help    | -h ) usage; exit 0;;
    --version | -V ) echo "$__scriptFile -- Version $__scriptVersion"; exit 0;;
    --section | -s ) section=$1; shift 1;;
    * ) break;;
    esac
done
main ${1:-$server}
