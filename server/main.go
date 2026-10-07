// Stunt Track Racer VR online server: relay and referee for 1-vs-1 races.
// Protocol: docs/net-protocol.md.
//
//	stunt-racer-server -port 27015 [-v] [-sim-latency 80ms] [-sim-loss 0.03]
package main

import (
	"flag"
	"log"
	"math/rand"
	"net"
	"time"
)

type inPacket struct {
	data []byte
	addr *net.UDPAddr
}

func main() {
	port := flag.Int("port", 27015, "UDP port")
	verbose := flag.Bool("v", false, "log sessions, rooms and results")
	simLatency := flag.Duration("sim-latency", 0, "testing: delay every packet the server sends")
	simLoss := flag.Float64("sim-loss", 0, "testing: drop this share (0..1) of the packets the server sends")
	flag.Parse()

	conn, err := net.ListenUDP("udp", &net.UDPAddr{Port: *port})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("listening on udp :%d", *port)

	addrs := map[string]*net.UDPAddr{}
	lossRng := rand.New(rand.NewSource(time.Now().UnixNano()))
	send := func(addr string, data []byte) {
		ua := addrs[addr]
		if ua == nil {
			return
		}
		if *simLoss > 0 && lossRng.Float64() < *simLoss {
			return
		}
		if *simLatency > 0 {
			time.AfterFunc(*simLatency, func() { conn.WriteToUDP(data, ua) })
			return
		}
		conn.WriteToUDP(data, ua)
	}
	sv := NewServer(time.Now(), time.Now().UnixNano(), send)
	sv.Verbose = *verbose

	in := make(chan inPacket, 1024)
	go func() {
		buf := make([]byte, 1500)
		for {
			n, addr, err := conn.ReadFromUDP(buf)
			if err != nil {
				log.Printf("read: %v", err)
				continue
			}
			in <- inPacket{data: append([]byte(nil), buf[:n]...), addr: addr}
		}
	}()

	tick := time.NewTicker(20 * time.Millisecond)
	for {
		select {
		case p := <-in:
			key := p.addr.String()
			addrs[key] = p.addr
			sv.Handle(p.data, key, time.Now())
		case now := <-tick.C:
			sv.Tick(now)
			// forget addresses without a session
			for k := range addrs {
				if sv.byAddr[k] == nil {
					delete(addrs, k)
				}
			}
		}
	}
}
