xquery version "3.1";

declare function local:get($url as xs:string, $offset as xs:integer)
as element() {
    let $url := ($url || $offset) => xs:anyURI(),
        $persist := false(),
        $request-headers := <headers>
                <header name="User-Agent" value="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML like Gecko) Chrome/51.0.2704.79 Safari/537.36 Edge/14.14931"/>
                <header name="Accept" value="*/*"/>
                <header name="Accept-Language" value="en-US,en;q=0.5"/>
                <header name="Referer" value="https://www.bundestag.de/service/opendata"/>
                <header name="X-Requested-With" value="XMLHttpRequest"/>
                <header name="DNT" value="1"/>
                <header name="Connection" value="close"/>
                <header name="Cookie" value="JSESSIONID=02F3424C15B7AB1E940918FA070B33E7.deliveryWorker; SERVERID=7b710496a8b88003f83ceb2525aef95f81af88f0"/>
            </headers>
    return
        httpclient:get($url, $persist, $request-headers)
};

declare function local:getDataUrls()
as xs:string+{
    let $baseUrl := "https://www.bundestag.de"
    let $url := $baseUrl || "/ajax/filterlist/de/service/opendata/-/543410/?offset="
    let $init := local:get($url, 0)
    let $hits := $init//@data-hits => number()
    let $listSize := 5
    let $iterations := ($hits div $listSize) => floor() => xs:integer()

return
    for $i in 0 to $iterations - 1
    let $offset := $i * $listSize
    return
        local:get($url, $offset)//*:a/string(@href) ! ($baseUrl || .)
};

declare function local:title($thisRedner) {
  let $thisRednerName := string( $thisRedner//name )
  let $fraktion := $thisRedner//fraktion/replace(., "[^a-zA-Z0-9]", "_")
  let $role := if(string($fraktion) != "") then $fraktion else ($thisRedner//rolle[1]/*)[1]/replace(., "[^a-zA-Z0-9]", "_")
  let $title := $role || "-" || $thisRedner//nachname/replace(string(.), "[^a-zA-Z0-9]", "_")
  return
    $title
};



let $links := local:getDataUrls()
let $collection := "/db/plenarsitzungen"
let $restart := if (xmldb:collection-available($collection))
                then (xmldb:remove($collection), xmldb:create-collection("/db", "plenarsitzungen"))
                else xmldb:create-collection("/db", "plenarsitzungen")

let $do :=
   for $link at $pos in $links
    let $doc := doc($link)
    let $sitzung := $doc/dbtplenarprotokoll/vorspann[1]/kopfdaten[1]/sitzungstitel[1]/sitzungsnr[1]/text() => format-number("000")
    let $sitzungs-collection := xmldb:create-collection($collection, $sitzung)
    let $store := xmldb:store($sitzungs-collection, $sitzung || ".xml", $doc)
    return
        for $top in $doc//tagesordnungspunkt
        let $id := replace(string($top/@top-id), "\W", "_")
        let $top-collection := xmldb:create-collection($sitzungs-collection, $id)
        let $store := xmldb:store($top-collection, $id || ".xml", $top)
        return
            for $rede in $top//rede
            let $redeId := string($rede/@id)
            let $thisRedner := ($rede/p[@klasse="redner"])[1]
            let $rednerId := string($thisRedner/redner/@id)
            let $title := local:title($thisRedner)
            let $rede-collection := xmldb:create-collection($top-collection, $title)
            let $title := $title || "-" || $redeId

            let $store1 := xmldb:store($rede-collection, $title || ".xml", $rede)

            let $ps := for $p at $pos in doc($store1)//p[@klasse != "redner"]

                        let $thisRednerNode := string( $p/preceding::redner[last()][@id = $rednerId]//name )
                        let $redner := $p/preceding::redner[1]/@id => string()
                        where $thisRednerNode eq $p/preceding::name[1]/string()
                        return
                            ($p/string() => replace("ä", "a#e") => replace("ö", "o#e")
                              => replace("ü", "u#e") => replace("ß", "s#s")
                              => replace("–", "-#-") => replace("Ä", "A#e")
                              => replace("Ö", "O#e") => replace("Ü", "U#e")
                              => replace("&#160;", " "))

            let $text := $ps
            let $theText := string-join($text, "&#10;") => replace("(\d) (\d\d\d)", "$1$2")
            let $hash := util:hash($theText, "SHA-256") => substring(1,6)
            let $filenameWOhash := $title || ".txt"
            let $filenameWhash := $title || "-" || $hash || ".txt"
            (: prevent overriding a resource :)
            let $txtfilename := if (xmldb:get-child-resources($rede-collection) =  $filenameWOhash)
                                then $filenameWhash
                                else $filenameWOhash

            let $zwischenfragen :=
              if(exists())
              then
                let $zwischenfragenCollection := xmldb:create-collection($top-collection, "zwischenfragen")
                return
                    for $redner in $doc($store1)//redner[@id != $rednerId]
                    let $zTitle := local:title($redner/parent::p)
              else ()
            return
                ($store1,
                xmldb:store-as-binary($rede-collection, $txtfilename, $theText))

return
  string-join(("", $do, ""), "&#10;")
