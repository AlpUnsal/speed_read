var GetURL = function() {};

GetURL.prototype = {
    run: function(args) {
        args.completionFunction({
            "baseURI": document.baseURI,
            "title": document.title,
            "html": document.documentElement.outerHTML,
            "url": document.URL
        });
    },
    
    finalize: function(args) {
        // cleanup
    }
};

var ExtensionPreprocessingJS = new GetURL();
