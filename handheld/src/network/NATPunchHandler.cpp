#include "NATPunchHandler.h"
#include "../raknet/HTTPConnection.h"
#include "../raknet/TCPInterface.h"
#include "PHPDirectoryServer2.h"

using namespace RakNet;
NATPuchHandler::NATPuchHandler() { tcpInterface = new TCPInterface; }
NATPuchHandler::~NATPuchHandler() { delete tcpInterface; }

void NATPuchHandler::initialize() { tcpInterface->Start(0, 64); }

void NATPuchHandler::registerToGameList(const RakNet::RakString &serverName,
                                        int port) {
  (void)serverName;
  (void)port;
}

void NATPuchHandler::removeFromGameList() {}

void NATPuchHandler::close() {}
