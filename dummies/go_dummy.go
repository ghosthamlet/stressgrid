// Running:
// $ go run server.go
//

package main

import (
    "fmt"
    "math/rand"
    "net/http"
    "time"
)

func handler(w http.ResponseWriter, r *http.Request) {
    message := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed mollis dictum ligula, ut sagittis nisl malesuada nec. Fusce hendrerit leo augue, nec pretium dolor porta sodales. Sed consequat sed purus eu aliquet. Etiam laoreet nibh vel ex sodales, non egestas lorem tempor. Pellentesque placerat facilisis felis, nec bibendum metus finibus quis. Donec lobortis, sapien at tristique placerat, nibh libero volutpat eros, eget mollis nibh elit et enim. Vestibulum consequat ut lorem sed eleifend. Ut eu dolor ut lectus faucibus rhoncus. Nam vestibulum vitae massa vel congue. Nam ac odio lacus. Nam condimentum ante eget mollis vestibulum. Cras nisi sapien, tempor nec diam at, vulputate cursus odio. Maecenas vitae tellus efficitur arcu mollis ultrices id vitae ex. Suspendisse potenti. Duis nec vestibulum dui. Donec ultricies sit amet lorem eu feugiat. Ut pretium vitae lectus at tempor. Curabitur condimentum arcu varius nulla ultricies, id feugiat odio dictum. Vivamus sollicitudin consectetur nullam.";
    time.Sleep((100 + (5 - time.Duration(rand.Int31n(10)))) * time.Millisecond)
    w.Write([]byte(message))
}

func main() {
    port := ":5000"

    http.HandleFunc("/", handler)

    fmt.Printf("Go dummy is listening on %s\n", port)

    if err := http.ListenAndServe(port, nil); err != nil {
        panic(err)
    }
}
