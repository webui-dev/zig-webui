window.pages = [
    {
        path: '/second-page',
        title: 'Second Page',
        html: '<h1>This is the SECOND page</h1><br/><a href="index.html">home</a>'
    },
    {
        path: '/third-page',
        title: 'Third Page',
        html: '<h1>This is the THIRD page</h1><br/><a href="index.html">home</a>'
    },
    {
        path: '/fourth-page',
        title: 'Fourth Page',
        html: '<h1>This is the FOURTH page</h1><br/><a href="index.html">home</a>'
    },
]
const pages = window.pages;

const router = function(path) {
    pages.forEach(route => {
        if(route.path === path) {
            window.history.pushState({}, route.title, path)
            document.getElementById('page').innerHTML = route.html
        }
    })
}
window.router = router