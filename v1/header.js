function init_header(val){
        var router_module=!!localStorage.getItem("router_module")?localStorage.getItem("router_module"):router.module;
        var tmpLogoSrc=new Image();
        tmpLogoSrc.src=(current_html == "guide" ? '../' : '')  +"images/logo.png";
        L = language[language_type]["JS"];
        var dfd = $.Deferred();
        var str = "";
        str += '        <div class="container-fluid">';
        str += '                <div class="row">';
        str += '                        <div class="col-md-8 col-md-offset-2" id="col-md">';
        str += '                                <div class="nav clearfix">';
        str += '                                        <div class="brand clearfix">';
if(router.vendor != "NEUTRAL"){
        str += '                                                <span class="navbar-brand">';
        str += '                                                        <img src="'+ (current_html == "guide" ? '../' : '')  +'images/logo.png">';
        str += '                                                </span>';
}
        str += '                                                <div class="" id="module" class="'+ router.vendor +'"><span>' + router.module + '</span></div>';

        str += '                                        </div>';
if(current_html != "guide"){

        str += '                                        <div id="menu-toggle-box" class="navbar-toggle" data-toggle="collapse" data-target="#menu-collapse"><span class="icon-bar"></span><span class="icon-bar"></span><span class="icon-bar"></span></div>';
}
        str += '                                        <div class="collapse" id="menu-collapse">';
        str += '        <div class="navbar-left">';
if(current_html != "guide" && current_html  != "login"){
        str += '<ul class="navigation clearfix">';
        str += '<li><a href="index.html">Главная</a></li>';
        str += '<li><a href="network.html">Сеть</a></li>';
        str += '<li><a href="application.html">Приложения</a></li>';
        str += '<li><a href="system.html">Инструменты</a></li>';
        str += '<li><a href="vless.html">VLESS</a></li>';
        str += '</ul>';
}
        str += '                                                </div>';
        str += '                                                <div class="navbar-right">';
        str += '                                                        <ul class="clearfix">';
if(current_html != "guide"){
        if(current_html != "login"){
                        str += '                                               <li><a class="hidden" id="official_website" href="http://' + router.official_website +'" target="_blank"><i class="website"></i>'+ language[language_type]["MENU"]["top-menu"]["official-website"] +'</a></li>';
                        str += '                                               <li><a href="javascript:;" onclick="signOut(true);"><i class="signout"></i>'+ language[language_type]["MENU"]["top-menu"]["login-out"] +'</a></li>';
                }
}

        str += '                                                               <li class="dropdown"><a href="javascript:void(0);" class="dropdown-toggle" data-toggle="dropdown"><i class="switch"></i><b id="current_lang"></b><b class="caret has-arrow"></b></a><ul id="lang_list" class="dropdown-menu"></ul></li>';
        str += '                                                        </ul>';
        str += '                                                </div>';
        str += '                                        </div>';
        str += '                                </div>';
        str += '                        </div>';
        str += '                </div>';
        str += '        </div>';
        $("#header").html(str);

        $(".navigation a").off(E).on(E,function(e){
                setPath("index");
        });

        str = "";
        str += '<div class="modal fade in" id="app-dialog" tabindex="-1">';
        str +=  '       <div class="modal-dialog">';
        str +=  '               <div class="modal-content">';
        str +=  '                       <div class="modal-header">';
        str +=  '                               <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">×</span></button>';
        str +=  '                       </div>';
        str +=  '                       <div class="modal-body">';
        str +=  '                               <div id="qrcode"></div>';
        str +=  '                       </div>';
        str +=  '               </div>';
        str +=  '       </div>';
        str +=  '</div>';
        $("body").append(str);

        dfd.resolve();
        initLanguageSwitch(val);

        $("#lang_list").val(val);
        return dfd.promise();
}

function changeMenuMediaQuery(){
        return; // Отключено
}

function changeMenuPos(){
        if(current_html != "login" && current_html != "guide"){
                var $element = $("#header .switch").parents("li");
                var $navbarLeft = $('#header .navbar-left');
                var $sms_li_wrapper = $('#header .sms_li_wrapper');

                if ($("#menu-toggle-box").is(":visible")) {
                        if ($element.hasClass('dropdown')) { $element.removeClass('dropdown'); }
                        if (!$element.hasClass('dropup')) { $element.addClass('dropup'); }
                }
                else {
                        if ($element.hasClass('dropup')) { $element.removeClass('dropup'); }
                        if (!$element.hasClass('dropdown')) { $element.addClass('dropdown'); }
                }
        }
}

function initLanguageSwitch(val){
        var arr = lang.langArr;
        var cur_lang = "";
        for(var i in arr){
                var $li = $("<li/>");
                var $a = $("<a/>");
                $a.attr("href","javascript:void(0)").html(arr[i].txt).attr("data-value",arr[i]["value"]).off(E).on(E,function(){
                        var value = $(this).attr("data-value");
                        if(val != value)
                                languageSwith(value);
                });

                if(arr[i]["value"] == val){
                        $li.attr("class","current");
                        $("#current_lang").html(arr[i].txt);
                }

                $li.append($a);
                $("#lang_list").append($li);
        }

        $('#header .dropdown').off("show.bs.dropdown").on("show.bs.dropdown", function () {
                $('#lang_list').css({
                        height: 'auto',
                        maxHeight: '300px',
                        overflowY: 'auto'
                });
        });
}

function languageSwith(val){
        if(typeof sessionStorage != "undefined")
                sessionStorage.setItem('language', val);
        window.location.reload();
}

function signOut(flag){
        if(!!!flag){
                if(!!router.rid && !!router.phoneId)
                        return;
        }
        if(current_html == "guide" || current_html  == "login"){
                return;
        }
        timer = {};
        var subdata='{"jsonrpc": "2.0", "id": 1, "method": "call", "params": [ "'+localStorage.getItem('token_id')+'", "session", "destroy", { } ] }';

        request({
                        url:"/ubus",
                        data:subdata
                }).done(function(data){
                        console.log(data);
                                data=JSON.stringify(data);
                    data = eval("(" + data + ")");
                    if(current_html!="guide"){
                         window.location.replace("login.html?s=exitcommand");
                    }
                }).fail(function(data){
                                show_message("error",L.exitFail);
                })
}

function expire_login_out(){
        var EXPIRE_TIME = 1000 * 60 * 15;
        var logoutTimer = null;

                logoutTimer && clearTimeout(logoutTimer);
                logoutTimer = setTimeout(signOut, EXPIRE_TIME);

                $('body').off("keyup click doubleclick").on("keyup click doubleclick",function (e) {
                        logoutTimer && clearTimeout(logoutTimer);
                        logoutTimer = setTimeout(signOut, EXPIRE_TIME);
                });
}

function paint_module_list(data,elem){
        $("#" + elem).html("");
        for(var i in data){
                if(data[i].display){
                        var $wrapper = $("<div/>");
                        $wrapper.attr({ "class":"col-xs-12 col-sm-4 col-md-3 col-lg-3 module-sec" });
                        var $a = $("<a/>");
                        var name = "";
                        if (data[i].id === "parent_management") {
                                if ((location.search.indexOf("phoneId") !== -1 || !!localStorage.getItem("phoneId"))){
                                        var url = "/resource/appIdentity/v1_0_0_240528/child_manage/index.html";
                                        if (location.search.indexOf("phoneId") !== -1) {
                                                url = url + location.search;
                                        } else {
                                                url = url + "?phoneId=" + localStorage.getItem("phoneId") + "&rid=" + localStorage.getItem("rid") + "&Language=" + localStorage.getItem("language");
                                        }
                                        $a.attr({ "class": "menu-item", "href": url });
                                        name = data[i].mobile_name;
                                } else {
                                        continue;
                                }
                        } else {
                                $a.attr({ "class": "menu-item", "href": data[i].id + ".html" });
                                name = data[i].name;
                        }
                        var $div = $("<div/>");
                        $div.attr({ "class":"menu-item-img" });
                        var $img = $("<img />");
                        $img.attr({ "src":data[i].image || "images/" + data[i].id + ".png" });
                        var $h3 = $("<h3/>");
                        $h3.html(data[i].name);
                        var $p = $("<p />");
                        $p.attr({ "class":"menu-item-p" });
                        $p.html(data[i].summary);
                        $div.append($img);
                        $a.append($div);
                        $a.append($h3);
                        $a.append($p);
                        $wrapper.append($a);
                        $("#" + elem).append($wrapper);
                        $a.off(E).on(E,function(e){ setFrom(e,this); });
                }
        }
}

var module_name = "";
function init_breadcrumbs(){
        var flag = false;
        if(typeof current_html == "undefined" || !!!current_html)
                return;
        for(var i in igd.module_list){
                if(flag) break;
                for(var j in igd.module_list[i].menu){
                        if(igd.module_list[i].menu[j].id == current_html){
                                $(".f-locationH3-container").html("");
                                $(".navigation a").removeClass("current");
                                var href = "";
                                if(typeof sessionStorage != "undefined"){
                                        var upperDir = sessionStorage.getItem("upperDir");
                                        if(!!upperDir && upperDir != ""){ module_name = upperDir; }
                                        else{ module_name = i; }
                                }
                                else module_name = i;

                                if(module_name == "system"){ href = "system.html"; $(".navigation a").eq(3).addClass("current"); }
                                else if(module_name == "application"){ href = "application.html"; $(".navigation a").eq(2).addClass("current"); }
                                else if(module_name == "network"){ href = "network.html"; $(".navigation a").eq(1).addClass("current"); }
                                else{ href = "index.html"; $(".navigation a").eq(0).addClass("current"); }

                                var str = '<div class="page-breadcrumb'+ (isApp().app ? " isApp" : "") +'">' +
                                        '<div class="container-fluid">' +
                                                '<div class="row">' +
                                                        '<div class="col-md-8 col-md-offset-2">' +
                                                                '<div class="c-breadcrumbs">' +
                                                                        '<ul class="clearfix">';
                                                                               if(!isApp().app)
                                                                               str += '<li><a class="pageUpper" href='+ href +'>'+ igd.module_list[module_name].title +'</a></li>';
                                                                               str += '<li class="pageTitle"><a href="javascript:void(0);" '+ (isApp().app ? '' : 'onclick="window.location.reload();"') +'>'+ igd.module_list[i].menu[j].name +'</a></li>';
                                                str += '</ul>' + '</div>' + '</div>' + '</div>' + '</div>' + '</div>'
                                $(".f-locationH3-container").html(str);
                                flag = true;
                                break;
                        }
                }
        }
        $(".pageUpper").off(E).on(E,function(e){ setPath("index"); });
}

function init_app_footer(){
        var elem = $(".app_bottom_menu");
        if(elem.length != 0) elem.remove();
        var str = "";
        str += '<div class="app_bottom_menu">';
        str +=  '       <a href='+ (current_html == "index" ? '"javascript:void(0)"' : '"index.html"') + 'class="item'+ ((module_name == "index" || (module_name == "" && current_html == "index")) ? " active\"" : "\"") +'>';
        str +=  '               <div class="col">';
        str +=  '                       <div class="app_bottom_icon index"></div>';
        str +=  '                       <strong>'+ language[language_type]["MENU"]["top-menu"]["index"] +'</strong>';
        str +=  '               </div>';
        str +=  '       </a>';
        str +=  '       <a href='+ (current_html == "network" ? '"javascript:void(0)"' : '"network.html"') + 'class="item'+ ((module_name == "network" || (module_name == "" && current_html == "network")) ? " active\"" : "\"") +'>';
        str +=  '               <div class="col">';
        str +=  '                       <div class="app_bottom_icon network"></div>';
        str +=  '                       <strong>'+ language[language_type]["MENU"]["top-menu"]["network"] +'</strong>';
        str +=  '               </div>';
        str +=  '       </a>';
        str +=  '       <a href='+ (current_html == "application" ? '"javascript:void(0)"' : '"application.html"') + 'class="item'+ ((module_name == "application" || (module_name == "" && current_html == "application")) ? " active\"" : "\"") +'>';
        str +=  '               <div class="col">';
        str +=  '                       <div class="app_bottom_icon application"></div>';
        str +=  '                       <strong>'+ language[language_type]["MENU"]["top-menu"]["application"] +'</strong>';
        str +=  '               </div>';
        str +=  '       </a>';
        str +=  '       <a href='+ (current_html == "system" ? '"javascript:void(0)"' : '"system.html"') + 'class="item'+ ((module_name == "system" || (module_name == "" && current_html == "system")) ? " active\"" : "\"") +'>';
        str +=  '               <div class="col">';
        str +=  '                       <div class="app_bottom_icon system"></div>';
        str +=  '                       <strong>'+ language[language_type]["MENU"]["top-menu"]["tools"] +'</strong>';
        str +=  '               </div>';
        str +=  '       </a>';
        str +=  '</div>';
        $(".g-wrapper").after(str);
}

function render_page_title(){
        var title = language[language_type]["VENDOR"]["NETIS"]["TITLE"];
        document.title = title.replace("{{module}}",router.module);
}