(function(){
  function ready(fn){ if(document.readyState!=='loading'){fn();} else {document.addEventListener('DOMContentLoaded', fn);} }
  ready(function(){
    var root = document.querySelector('.rl-login, .b-login-form, form');
    if(!root){return;}
    var logo = document.createElement('div');
    logo.className='unicode-brand';
    logo.innerHTML='<img src="./?/Plugin/UnicodePlugin/0/assets/logo.svg" style="max-width:160px" alt="UNICODE"/><div class="name">UNICODE</div><div class="slogan">SECURE · FAST · LIMITLESS<br/>代码无界 未来无限</div>';
    var h = document.querySelector('h1,h2,.title');
    if(h){ h.style.display='none'; h.parentNode.insertBefore(logo,h); }

    var pw = document.querySelector('input[type="password"]');
    var btn = root.querySelector('button[type="submit"],button');
    if(pw && btn){
      var w = document.createElement('div');
      w.id='unicode-turnstile';
      w.style.margin='12px 0';
      btn.parentNode.insertBefore(w,btn);
    }

    document.querySelectorAll('[href*="themes"], [data-i18n*="theme"]').forEach(function(el){el.style.display='none';});
    document.querySelectorAll('.modal,.notification,.welcome').forEach(function(el){if((el.textContent||'').match(/欢迎|welcome/i)){el.style.display='none';}});
  });
})();
