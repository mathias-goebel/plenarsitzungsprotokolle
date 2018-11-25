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
            let $fraktion := $rede/p[@klasse="redner"][1]//fraktion/replace(., "[^a-zA-Z0-9]", "_")
            let $rednerId := string( $rede/p[@klasse="redner"][1]/redner/@id )
            let $role := if(string($fraktion) != "") then $fraktion else ($rede/p[@klasse="redner"][1]//rolle[1]/*)[1]/replace(., "[^a-zA-Z0-9]", "_")
            let $title := $role || "-" || $rede/p[@klasse="redner"][1]//nachname/replace(string(.), "[^a-zA-Z0-9]", "_")
            let $rede-collection := xmldb:create-collection($top-collection, $title)
            let $title := $title || "-" || $redeId
            let $text :=
                for $redePart in $rede//p[@klasse = "redner"][./redner/@id = $rednerId]
                return
                    ($redePart/following-sibling::p[ not(./preceding-sibling::name[1] >> $redePart) ]
                    /string() !
                        (.  => replace("ä", "ae") => replace("ö", "oe")
                            => replace("ü", "ue") => replace("ß", "ss")
                            => replace("–", "-") => replace("&#160;", " ")
                        ),
                      "")
            return
                (xmldb:store($rede-collection, $title || ".xml", $rede),
                xmldb:store-as-binary($rede-collection, $title || ".txt", string-join($text, "&#10;")))

return
  string-join(("", $do, ""), "&#10;")
