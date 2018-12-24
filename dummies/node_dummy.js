// content of index.js
const http = require('http')
const port = 5000

const requestHandler = (request, response) => {
  body = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed mollis dictum ligula, ut sagittis nisl malesuada nec. Fusce hendrerit leo augue, nec pretium dolor porta sodales. Sed consequat sed purus eu aliquet. Etiam laoreet nibh vel ex sodales, non egestas lorem tempor. Pellentesque placerat facilisis felis, nec bibendum metus finibus quis. Donec lobortis, sapien at tristique placerat, nibh libero volutpat eros, eget mollis nibh elit et enim. Vestibulum consequat ut lorem sed eleifend. Ut eu dolor ut lectus faucibus rhoncus. Nam vestibulum vitae massa vel congue. Nam ac odio lacus. Nam condimentum ante eget mollis vestibulum. Cras nisi sapien, tempor nec diam at, vulputate cursus odio. Maecenas vitae tellus efficitur arcu mollis ultrices id vitae ex. Suspendisse potenti. Duis nec vestibulum dui. Donec ultricies sit amet lorem eu feugiat. Ut pretium vitae lectus at tempor. Curabitur condimentum arcu varius nulla ultricies, id feugiat odio dictum. Vivamus sollicitudin consectetur nullam.';
  setTimeout(() => {
    response.end(body)
  }, (100 + (5 - (Math.random() * 10))));
}

const server = http.createServer(requestHandler)

server.listen(port, (err) => {
  if (err) {
    return console.log('something bad happened', err)
  }

  console.log(`Node dummy is listening on port ${port}`)
})
