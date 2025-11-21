const config = {
    site: "my site",
    dev: "js",
}
window.addEventListener("load", (ev) => {
    console.log(config);
    console.log("event", ev);
    let header = document.getElementById("header");
    header.insertAdjacentText("beforebegin", config.site);
} );
